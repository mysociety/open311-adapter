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

package Integrations::Alloy::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Alloy';
sub _build_config_file { path(__FILE__)->sibling("alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::DummyNCC;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Northamptonshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummyncc';
    $args{config_file} = path(__FILE__)->sibling("alloy.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Alloy::Dummy');
sub service_request_content { '/open311/service_request_extended' }

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

my $endpoint = Open311::Endpoint::Integration::UK::DummyNCC->new;

my %responses = (
    resource => '{
    }',
);

my @sent;
my @calls;

my $integration = Test::MockModule->new('Integrations::Alloy');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};

    my $content = '[]';
    push @calls, $call;
    if ( $body ) {
        push @sent, $body;
        if ( $call =~ 'search/resource-fetch' ) {
            my $type = $body->{aqsNode}->{properties}->{entityCode};
            my $time = $body->{aqsNode}->{children}->[0]->{children}->[1]->{properties}->{value}->[0];
            if ( $type =~ /DEFECT/ ) {
                if ( $time =~ /2019-01-02/ ) {
                    $content = path(__FILE__)->sibling('json/alloy/defect_search_all.json')->slurp;
                } else {
                    $content = '{"totalPages": 1, "results":[]}';
                }
            } elsif ( $type =~ /INSPECT/ ) {
                $content = path(__FILE__)->sibling('json/alloy/ncc_inspect_search.json')->slurp;
            } else {
                $content = '{"totalPages": 1, "results":[]}';
            }
        } elsif ( $call eq 'resource/12345' ) {
            $content = '{ "systemVersionId": 8011 }';
        }
    } else {
        if ( $call eq 'reference/value-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/reference_value_type.json')->slurp;
        } elsif ( $call eq 'source-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/source_type.json')->slurp;
        } elsif ( $call eq 'source' ) {
            $content = path(__FILE__)->sibling('json/alloy/source.json')->slurp;
        } elsif ( $call eq 'resource/745874' ) {
            $content = '{ "title": "P1, P1 - 2 weeks" }';
        } elsif ( $call eq 'resource/745883' ) {
            $content = '{ "title": "P2, P2 - 4 weeks" }';
        } elsif ( $call eq 'projection/point' ) {
            $content = '{ "x": 1, "y": 2 }';
        } elsif ( $call eq 'resource/3027029/parents' ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call eq 'resource/4947504/parents' ) {
            $content = '{ "details": { "parents": [ {"actualParentSourceTypeId": 1001181, "parentResId": 3027030 } ] } }';
        } elsif ( $call =~ m#resource/[0-9]*/parents# ) {
            $content = '{ "details": { "parents": [] } }';
        } elsif ( $call eq 'resource/12345/full' ) {
            $content = '{ "resourceId": 12345, "values": [ { "attributeId": 1013262, "value": "Original text" } ], "version": { "currentSystemVersionId": 8001, "resourceSystemVersionId": 8000 } }';
        } elsif ( $call eq 'resource/3027029/versions' ) {
            $content = path(__FILE__)->sibling('json/alloy/resource_versions.json')->slurp;
        } elsif ( $call eq 'resource/3027029/full?systemVersion=272125' ) {
            $content = path(__FILE__)->sibling('json/alloy/ncc_resource_3027029_v272125.json')->slurp;
        } elsif ( $call eq 'source-type' ) {
            $content = path(__FILE__)->sibling('json/alloy/source_type.json')->slurp;
        } elsif ( $call eq 'source' ) {
            $content = path(__FILE__)->sibling('json/alloy/source.json')->slurp;
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result = decode_json(encode_utf8($content));
    return $result;
});

subtest "check fetch problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/requests.json?jurisdiction_id=dummyncc&start_date=2019-01-02T00:00:00Z&end_date=2019-01-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [{
      long => 1,
      requested_datetime => "2019-01-02T11:29:16Z",
      service_code => "Bus Stops_Shelter Damaged",
      updated_datetime => "2019-01-02T11:29:16Z",
      service_name => "Shelter Damaged",
      address_id => "",
      lat => 2,
      description => "Our Inspector has identified a Bus Stops defect at this location and has issued a works ticket to repair under the Shelter Damaged category. We aim to complete this work within the next 2 weeks.",
      service_request_id => 4947505,
      zipcode => "",
      media_url => "",
      status => "investigating",
      address => ""
   },
   {
      address_id => "",
      lat => 2,
      service_request_id => 4947597,
      description => "Our Inspector has identified a Winter defect at this location and has issued a works ticket to repair under the Grit Bin - empty/refill category. We aim to complete this work within the next 4 weeks.",
      service_name => "Grit Bin - empty/refill",
      status => "fixed",
      media_url => "",
      address => "",
      zipcode => "",
      requested_datetime => "2019-01-02T14:44:53Z",
      long => 1,
      updated_datetime => "2019-01-02T14:44:53Z",
      service_code => "Winter_Grit Bin - empty/refill"
   }], "correct json returned";
};

subtest "create comment" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/servicerequestupdates.json', 
        jurisdiction_id => 'dummyncc',
        api_key => 'test',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'This is an update',
        service_request_id => 12345,
        update_id => 999,
        status => 'OPEN',
        updated_datetime => '2019-04-17T14:39:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply $sent,
    {
    attributes =>         {
        1013262 => "Original text
Customer Bob Mould [test\@example.com] update at 2019-04-17 14:39:00
This is an update"
    },
    systemVersionId => 8000
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "update_id" => 8011
        } ], 'correct json returned';

};

subtest "further investigation updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-01T00:00:00Z&end_date=2019-03-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'investigating',
        external_status_code => 'further',
        service_request_id => '3027029',
        description => 'This is a customer response',
        updated_datetime => '2019-01-01T00:32:40Z',
        update_id => '271882',
        media_url => '',
    } ], 'correct json returned';
};

restore_time();
done_testing;
