package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Lincolnshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling("confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');

package main;

use strict;
use warnings;
use Test::More;
use Test::LongString;
use Test::MockModule;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    $op = $op->value;
    if ($op->name eq 'GetEnquiryStatusChanges') {
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
            { EnquiryNumber => 2020, EnquiryStatusLog => [ { EnquiryLogNumber => 5, LogEffectiveTime => '2022-10-23T12:00:00Z', LoggedTime => '2022-10-23T12:00:00Z', EnquiryStatusCode => 'FIX' } ] },
        ] } } };
    }
    return {};
});

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "fetching of completion photos" => sub {
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [], '{"primaryJobNumber":"432"}') if $req->uri =~ /enquiries\/2020/;
        return HTTP::Response->new(200, 'OK', [], '{"documents":[
            {"documentNo":1,"fileName":"photo1.jpeg","documentNotes":"Before"},
            {"documentNo":2,"fileName":"photo2.jpeg","documentNotes":"After"}
            ]}') if $req->uri =~ /jobs\/432/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photo/completion?jurisdiction_id=lincolnshire_confirm&amp;job=432&amp;photo=2</media_url>';
};

done_testing;
