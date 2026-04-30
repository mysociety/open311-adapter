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

package Integrations::Confirm::DummyGraphQL;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("lincolnshire_graphql.yml")->stringify }

package Open311::Endpoint::Integration::UK::DummyGraphQL;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Lincolnshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling("lincolnshire_graphql.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::DummyGraphQL');

package Open311::Endpoint::Integration::UK::Dummy::Lincolnshire;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Lincolnshire';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling("lincolnshire.yml")->stringify;
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
    contains_string $res->content, '<media_url>http://confirm/photos?jurisdiction_id=lincolnshire_confirm&amp;job=432&amp;photo=2</media_url>';
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
        GET => '/photos?jurisdiction_id=lincolnshire_confirm&job=432&photo=2'
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

my $graphql_endpoint = Open311::Endpoint::Integration::UK::DummyGraphQL->new;
my $graphql_integration = Test::MockModule->new('Integrations::Confirm');

subtest "only 'after' photos are included in updates from GraphQL" => sub {
    $graphql_integration->mock(perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {
                        enquiryNumber => '3001',
                        enquiryStatusCode => 'FIX',
                        logNumber => '5',
                        loggedDate => '2022-10-23T12:00:00Z',
                        notes => '',
                        centralEnquiry => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            enquiryLink => {
                                job => {
                                    documents => [
                                        {
                                            url => "/ConfirmWeb/api/123/attachments/JOB/432/1",
                                            documentName => "before.jpg",
                                            documentDate => '2022-10-23T12:00:00Z',
                                            documentNotes => 'Before',
                                        },
                                        {
                                            url => "/ConfirmWeb/api/123/attachments/JOB/432/2",
                                            documentName => "after.jpg",
                                            documentDate => '2022-10-23T12:00:00Z',
                                            documentNotes => 'After',
                                        },
                                    ]
                                }
                            }
                        }
                    }
                ]
            }
        };
    });
    my $res = $graphql_endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, 'attachments%2FJOB%2F432%2F2', 'after photo is included';
    unlike $res->content, qr/attachments%2FJOB%2F432%2F1/, 'before photo is excluded';
    $graphql_integration->unmock('perform_request_graphql');
};

subtest "no photos returned when all are 'before'" => sub {
    $graphql_integration->mock(perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {
                        enquiryNumber => '3001',
                        enquiryStatusCode => 'FIX',
                        logNumber => '5',
                        loggedDate => '2022-10-23T12:00:00Z',
                        notes => '',
                        centralEnquiry => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            enquiryLink => {
                                job => {
                                    documents => [
                                        {
                                            url => "/ConfirmWeb/api/123/attachments/JOB/432/1",
                                            documentName => "before.jpg",
                                            documentDate => '2022-10-23T12:00:00Z',
                                            documentNotes => 'Before',
                                        },
                                    ]
                                }
                            }
                        }
                    }
                ]
            }
        };
    });
    my $res = $graphql_endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url></media_url>', 'no photos returned when all are before';
    $graphql_integration->unmock('perform_request_graphql');
};

subtest 'cope with defaults of fetched enquiries' => sub {
    $open311->mock(perform_request => sub {
        my ($self, $op) = @_; # Don't care about subsequent ops
        $op = $$op;
        if ($op->name && $op->name eq 'GetEnquiryLookups') {
            return {
                OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                    { ServiceCode => 'HMOB', ServiceName => 'HMOB', EnquirySubject => [
                        { SubjectCode => "MO02" },
                        { SubjectCode => "MO05" },
                        { SubjectCode => "MO06" },
                        { SubjectCode => "MO10" },
                    ] },
                    { ServiceCode => 'SD', ServiceName => 'SD', EnquirySubject => [
                        { SubjectCode => "HSF9" },
                    ] },
                    { ServiceCode => 'PRWD', ServiceName => 'PRWD', EnquirySubject => [
                        { SubjectCode => "RW41" },
                    ] },
                    { ServiceCode => 'HMVG', ServiceName => 'HMVG', EnquirySubject => [
                        { SubjectCode => "MV05" },
                    ] },
                ] } }
            };
        } elsif ( $op->name && $op->name eq 'GetEnquiry' ) {
            return { OperationResponse => [
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'HMOB', SubjectCode => 'MO02', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'HMOB', SubjectCode => 'MO05', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'HMOB', SubjectCode => 'MO06', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'HMOB', SubjectCode => 'MO10', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'HMVG', SubjectCode => 'MV05', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'PRWD', SubjectCode => 'RW41', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
              } } },
              { GetEnquiryResponse => { Enquiry => {
                ServiceCode => 'SD', SubjectCode => 'HSF9', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
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

    my $endpoint = Open311::Endpoint::Integration::UK::Dummy::Lincolnshire->new;
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

    my @reports = split /<request>/, $res->content;

    my @out = (
        { group => 'Pavement and verge', service_code => 'TRIP_HAZARD', osc => 'SD_HSF9' },
        { group => 'PROW', service_code => 'PROW_TREES', osc => 'PRWD_RW41' },
        { group => 'Trees', service_code => 'HMVG_MV05_1' },
        { group => 'Trees', service_code => 'TREE_HANGING', osc => 'HMOB_MO10_1' },
        { group => "Roads and cycleways", service_code => 'HMOB_MO06' },
        { group => "Roads and cycleways", service_code => 'HMOB_MO05' },
        { group => 'Trees', service_code => 'TREES_FALLEN', osc => 'HMOB_MO02_2' },
    );

    foreach (@out) {
        my $r = pop @reports;
        contains_string $r, "<group>$_->{group}</group>";
        contains_string $r, "<service_code>$_->{service_code}</service_code>";
        contains_string $r, "<original_service_code>$_->{osc}</original_service_code>"
            if $_->{osc};
    }
};

done_testing;
