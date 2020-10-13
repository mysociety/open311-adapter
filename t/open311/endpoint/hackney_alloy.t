package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';
use utf8;

has content => (
    is => 'ro',
    isa => Str,
    default => '[]',
    coerce => sub { encode_utf8($_[0]) }
);

has code => (
    is => 'ro',
    isa => Str,
    default => '200',
);

has message => (
    is => 'ro',
    isa => Str,
    default => 'OK',
);

has is_success => (
    is => 'ro',
    isa => Bool,
    default => 1
);

package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
use HTTP::Response;
use HTTP::Headers;

extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("alloyv2_hackney.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Hackney';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("alloyv2_hackney.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');
sub service_request_content { '/open311/service_request_extended' }

sub _get_attachments {
    my $h = HTTP::Headers->new;
    $h->header('Content-Disposition' => 'filename: "file.jpg"');
    return HTTP::Response->new(200, 'OK', $h, "\x{ff}\x{d8}this is data");
}

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my %responses = (
    resource => '{
    }',
);

my (@sent, %sent, @calls);

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};
    my $is_file = $args{is_file};

    my $content_type;
    my $content = '[]';
    push @calls, $call;
    if ( $is_file ) {
        $sent{$call} = $body;
        push @sent, $body;
        return { fileItemId => 'fileid' };
    } elsif ( $body ) {
        $sent{$call} = $body;
        push @sent, $body;
        if ( $call =~ 'aqs/statistics' ) {
            $content = '{ "page":1,"pageSize":20,"results":[{"value":{"attributeCode":"attributes_fake","value":4.0}}] }';
        } elsif ( $call =~ 'aqs/query' ) {
            my $type = $body->{aqs}->{properties}->{dodiCode};
            my $time = $body->{aqs}->{children}->[0]->{children}->[1]->{properties}->{value}->[0];
            $content = '{}';
            if ( $type =~ /Inspect/ && $time =~ /2020-10-12/ ) {
                $content = path(__FILE__)->sibling('json/alloyv2/inspect_search_photo.json')->slurp;
            }
        } elsif ( $call =~ 'item-log/item/([^/]*)/reconstruct' ) {
            my $id = $1;
            my $date = $body->{date};
            $date =~ s/\D//g;
            $content = path(__FILE__)->sibling("json/alloyv2/reconstruct_${id}_$date.json")->slurp;
        }
    } else {
        if ( $call eq 'design/designs_enquiryInspectionRFS1001181_5d3245c5fe2ad806f8dfbaf6' ) {
            $content = path(__FILE__)->sibling('json/alloyv2/design_rfs.json')->slurp;
        } elsif ( $call =~ 'item-log/item/(.*)$' ) {
            $content = path(__FILE__)->sibling("json/alloyv2/item_log_$1.json")->slurp;
        } elsif ( $call =~ 'file/(\w+)' ) {
            $content_type = 'image/jpeg';
            $content = 'This is a photo';
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result;
    if ( $content_type ) {
        my $res = HTTP::Response->new(
            200,
            'OK',
            [ 'Content-Type' => $content_type ],
            $content,
        );
        return $res;
    } else {
        eval {
        $result = decode_json(encode_utf8($content));
        };
        if ($@) {
            warn $@;
            warn $content;
            return decode_json('[]');
        }
        return $result;
    }
});


subtest "update with a photo" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2020-10-12T11:00:00Z&end_date=2020-10-12T14:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
        {
            status => 'in_progress',
            service_request_id => '4027032',
            description => '',
            updated_datetime => '2020-10-12T12:00:00Z',
            update_id => '5d32469bb4e1b90150014307',
            media_url => 'http://localhost/photo/completion?jurisdiction_id=hackney_highways_alloy_v2&job=4027032&photo=654321',
        },
        {
            status => 'investigating',
            service_request_id => '4027029',
            description => '',
            updated_datetime => '2020-10-12T12:03:04Z',
            update_id => '5d32469bb4e1b90150014306',
            media_url => '',
        },
        {
            status => 'fixed',
            service_request_id => '4027027',
            description => '',
            updated_datetime => '2020-10-12T12:15:00Z',
            update_id => '4d32469bb4e1b90150014309',
            media_url => 'http://localhost/photo/completion?jurisdiction_id=hackney_highways_alloy_v2&job=4027027&photo=457890',
        }
    ], 'correct json returned';
};

subtest "fetch a photo" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/photo/completion?jurisdiction_id=dummy&photo=1234&job=1234',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is $res->header('Content-Type'), 'image/jpeg', 'correct header';
    is $res->content, 'This is a photo', 'correct content';
};

restore_time();
done_testing;
