package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling('southwark_graphql.yml')->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'confirm_dummy';
    $args{config_file}
        = path(__FILE__)->sibling('southwark_graphql.yml')->stringify;
    return $class->$orig(%args);
};
has integration_class => ( is => 'ro', default => 'Integrations::Confirm::Dummy' );

use Test::LongString;
use Test::MockModule;
use Test::More;

BEGIN { $ENV{TEST_MODE} = 1 }

my $confirm_integration = Test::MockModule->new('Integrations::Confirm');
my $confirm_endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

sub empty_json { HTTP::Response->new( 200, 'OK', [], '{}' ) }
$confirm_integration->mock( perform_request => \&empty_json );

subtest 'fetching completion photos' => sub {
    $confirm_integration->mock( perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {   enquiryNumber     => '1001',
                        enquiryStatusCode => 'CAG',
                        logNumber         => '1',
                        loggedDate        => '2026-01-01T00:00:00Z',
                        notes             => '',
                        centralEnquiry    => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            documents => [
                                {   url =>
                                        "/ConfirmWeb/api/tenant/attachments/ENQUIRY/123/1",
                                    documentName => "photo_1.jpg",
                                    documentDate =>
                                        '2026-01-01T00:00:00Z',
                                },
                                {   url =>
                                        "/ConfirmWeb/api/tenant/attachments/ENQUIRY/123/2",
                                    documentName => "photo_2.jpg",
                                    documentDate =>
                                        '2026-01-01T00:00:00Z',
                                },
                            ]
                        }
                    }
                ]
            }
        };
    } );

    my $res = $confirm_endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2026-01-01T00:00:00Z&end_date=2026-01-01T01:00:00Z',
    );

    ok $res->is_success, 'valid request' or diag $res->content;

    contains_string $res->content,
        '<media_url>http://confirm/photos?jurisdiction_id=confirm_dummy&amp;doc_url=%2F1</media_url>';
    contains_string $res->content,
        '<media_url>http://confirm/photos?jurisdiction_id=confirm_dummy&amp;doc_url=%2F2</media_url>';
};

subtest 'photos not fetched for enquiries not marked as closed' => sub {
    $confirm_integration->mock( perform_request_graphql => sub {
        return {
            data => {
                enquiryStatusLogs => [
                    {   enquiryNumber     => '1001',
                        enquiryStatusCode => 'IM',
                        logNumber         => '1',
                        loggedDate        => '2026-01-01T00:00:00Z',
                        notes             => '',
                        centralEnquiry    => {
                            subjectCode => 'DEF',
                            serviceCode => 'ABC',
                            documents => [
                                {   url =>
                                        "/ConfirmWeb/api/tenant/attachments/ENQUIRY/123/1",
                                    documentName => "photo_1.jpg",
                                    documentDate =>
                                        '2026-01-01T00:00:00Z',
                                },
                                {   url =>
                                        "/ConfirmWeb/api/tenant/attachments/ENQUIRY/123/2",
                                    documentName => "photo_2.jpg",
                                    documentDate =>
                                        '2026-01-01T00:00:00Z',
                                },
                            ]
                        }
                    }
                ]
            }
        };
    } );

    my $res = $confirm_endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2026-01-01T00:00:00Z&end_date=2026-01-01T01:00:00Z',
    );

    ok $res->is_success, 'valid request' or diag $res->content;

    contains_string $res->content,
        '<media_url></media_url>';
};

done_testing;
