use strict;
use warnings;
use Test::More;
use Test::LongString;
use Test::MockModule;

BEGIN { $ENV{TEST_MODE} = 1; }

use Open311::Endpoint::Integration::UK;

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

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Graffiti', EnquirySubject => [ { SubjectCode => "DEF" } ] },
            ] } }
        };
    } elsif ( $op->name && $op->name eq 'GetEnquiry' ) {
        return { OperationResponse => [
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
          } } },
        ] };
    }
    $op = $op->value;
    if ($op->name eq 'GetEnquiryStatusChanges') {
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
            { EnquiryNumber => 2003, EnquiryStatusLog => [ { EnquiryLogNumber => 5, LogEffectiveTime => '2022-10-23T12:00:00Z', LoggedTime => '2022-10-23T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2020, EnquiryStatusLog => [ { EnquiryLogNumber => 5, LogEffectiveTime => '2022-10-23T12:00:00Z', LoggedTime => '2022-10-23T12:00:00Z', EnquiryStatusCode => 'FIX' } ] },
        ] } } };
    }
    return {};
});

subtest "bad look up of completion photo" => sub {
    my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(404, 'Not found', [], '<html><body>Hmm</body></html>') if $req->uri =~ /enquiries\/2020/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url></media_url>';
};

subtest "looking up of completion photos" => sub {
    my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [], '{"jobNumber":"432"}') if $req->uri =~ /enquiries\/2020/;
        return HTTP::Response->new(200, 'OK', [], '{"documents":[
            {"documentNo":1,"fileName":"photo1.jpeg","documentNotes":"Before"},
            {"documentNo":2,"fileName":"photo2.jpeg","documentNotes":"After"}
            ]}') if $req->uri =~ /jobs\/432/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://confirm/photo/completion?jurisdiction_id=lincolnshire_confirm&amp;job=432&amp;photo=2</media_url>';
};

subtest 'fetching of completion photos' => sub {
    my $endpoint = Open311::Endpoint::Integration::UK->new;
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [Content_Type => 'image/jpeg'], 'data') if $req->uri =~ /documents\/0/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/photo/completion?jurisdiction_id=lincolnshire_confirm&job=432&photo=2'
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    is $res->content, 'data';
};

subtest 'pass user forename, surname and email from Confirm in Get Service Requests call' => sub {
    my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [], '{"customers":[{"contact":{"fullName":"John Smith", "email":"john@example.org"}}]}') if $req->uri =~ /enquiries\/2003/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/requests.xml?jurisdiction_id=lincolnshire_confirm&start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<contact_name>John Smith</contact_name>';
    contains_string $res->content, '<contact_email>john@example.org</contact_email>';

};

done_testing;
