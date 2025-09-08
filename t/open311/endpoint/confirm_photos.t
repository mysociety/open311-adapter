package Integrations::Confirm::DummyPhotos;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm_photos.yml")->stringify }

package Integrations::Confirm::DummyPhotosGraphQL;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm_photos_graphql.yml")->stringify }

package Open311::Endpoint::Integration::UK::DummyPhotos;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_photos';
    $args{config_file} = path(__FILE__)->sibling("confirm_photos.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::DummyPhotos');

package Open311::Endpoint::Integration::UK::DummyPhotosGraphQL;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_photos_graphql';
    $args{config_file} = path(__FILE__)->sibling("confirm_photos_graphql.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::DummyPhotosGraphQL');

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $integration = Test::MockModule->new('Integrations::Confirm');
my $endpoint = Open311::Endpoint::Integration::UK::DummyPhotos->new;
my $endpoint_graphql = Open311::Endpoint::Integration::UK::DummyPhotosGraphQL->new;

my $lwp = Test::MockModule->new('LWP::UserAgent');
sub empty_json { HTTP::Response->new(200, 'OK', [], '{}') }
$lwp->mock(request => \&empty_json);

$integration->mock(perform_request => \&empty_json);

subtest "fetching of job photos for enquiry update" => sub {
    $integration->mock(perform_request => sub {
        return {
            OperationResponse => {
                GetEnquiryStatusChangesResponse => {
                    UpdatedEnquiry => [
                        {
                            EnquiryNumber => 2020,
                            EnquiryStatusLog => [
                                {
                                    EnquiryLogNumber => 2,
                                    StatusLogNotes => 'status log notes',
                                    LogEffectiveTime => '2025-01-01T00:00:00Z',
                                    LoggedTime => '2025-01-01T00:00:00Z',
                                    EnquiryStatusCode => 'FIX'
                                }
                            ]
                        }
                    ]
                }
            }
        }
    });

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
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photos?jurisdiction_id=confirm_dummy_photos&amp;job=432&amp;photo=1</media_url>';

    $lwp->mock(request => \&empty_json);
    $integration->mock(perform_request => \&empty_json);
};

subtest "fetching of job photos for enquiry update via GraphQL" => sub {
    $integration->mock(perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {
                        enquiryNumber => '3001',
                        enquiryStatusCode => 'FIX',
                        logNumber => '3',
                        loggedDate => '2025-01-01T00:00:00Z',
                        notes => '',
                        centralEnquiry => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            enquiryLink => {
                                job => {
                                    documents => [
                                        {
                                            url => "/ConfirmWeb/api/tenant/attachments/JOB/123/1",
                                            documentName => "photo.jpg"
                                        }
                                    ]
                                }
                            }
                        }
                    }
                ]
            }
        };
    });

    my $res = $endpoint_graphql->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photos?jurisdiction_id=confirm_dummy_photos_graphql&amp;doc_url=%2Fattachments%2FJOB%2F123%2F1</media_url>';

    $lwp->mock(request => \&empty_json);
    $integration->unmock('perform_request_graphql');
};


subtest "fetching of defect photos for enquiry update via GraphQL" => sub {
    $integration->mock(perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {
                        enquiryNumber => '3001',
                        enquiryStatusCode => 'RAISED',
                        logNumber => '3',
                        loggedDate => '2025-01-01T00:00:00Z',
                        notes => '',
                        centralEnquiry => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            enquiryLink => {
                                defect => {
                                    documents => [
                                        {
                                            url => "/ConfirmWeb/api/tenant/attachments/DEFECT/123/1",
                                            documentName => "photo.jpg"
                                        }
                                    ]
                                }
                            }
                        }
                    }
                ]
            }
        };
    });

    my $res = $endpoint_graphql->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photos?jurisdiction_id=confirm_dummy_photos_graphql&amp;doc_url=%2Fattachments%2FDEFECT%2F123%2F1</media_url>';

    $lwp->mock(request => \&empty_json);
    $integration->unmock('perform_request_graphql');
};

subtest "fetching of job photos for defect update via GraphQL" => sub {
    $integration->mock(perform_request_graphql => sub {
        return {
            data => {
                jobStatusLogs => [
                    {
                        loggedDate => '2025-01-01T00:00:00Z',
                        statusCode => 'FIXED',
                        key => 'key',
                        job => {
                            documents => [
                                {
                                    url => "/ConfirmWeb/api/tenant/attachments/JOB/123/1",
                                    documentName => "photo.jpg"
                                }
                            ],
                            defects => [
                                {
                                    defectNumber => 1,
                                    targetDate => '2025-01-01T00:00:00Z',
                                }
                            ]
                        }
                    }
                ]
            }
        };
    });

    my $res = $endpoint_graphql->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photos?jurisdiction_id=confirm_dummy_photos_graphql&amp;doc_url=%2Fattachments%2FJOB%2F123%2F1</media_url>';

    $lwp->mock(request => \&empty_json);
    $integration->unmock('perform_request_graphql');
};


subtest "fetching of defect photos for defect fetch" => sub {
    $integration->mock(perform_request_graphql => sub {
        my ( $self, %args ) = @_;

        $args{type} ||= '';
        $args{query} ||= '';

        if ( $args{type} eq 'defects' ) {
            return {
                data => {
                    defects => [
                        {
                            defectNumber => 1,
                            easting => 1,
                            northing => 1,
                            loggedDate => '2025-01-01T00:00:00Z',
                            targetDate => '2025-01-01T00:00:00Z',
                            defectType => {
                                code => "SLDA",
                            },
                            documents => [
                                {
                                    url => "/ConfirmWeb/api/tenant/attachments/DEFECT/123/1",
                                    documentName => "photo.jpg"
                                }
                            ],
                        }
                    ]
                }
            };
        } elsif ( $args{type} eq 'defect_types' ) {
            return {
                data => {
                    defectTypes => [
                        { code => 'SLDA', name => 'Defective Street Light' },
                    ],
                },
            };
        }
        return {};
    });

    my $res = $endpoint_graphql->run_test_request(
        GET => '/requests.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photos?jurisdiction_id=confirm_dummy_photos_graphql&amp;doc_url=%2Fattachments%2FDEFECT%2F123%2F1</media_url>';

    $lwp->mock(request => \&empty_json);
    $integration->unmock('perform_request_graphql');
};

done_testing;
