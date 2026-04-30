package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm_defect_extras.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy';
    $args{config_file} = path(__FILE__)->sibling("confirm_defect_extras.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');


package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }


my $integration = Test::MockModule->new("Integrations::Confirm");
my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $lwp = Test::MockModule->new('LWP::UserAgent');
sub empty_json { HTTP::Response->new(200, 'OK', [], '{}') }
$lwp->mock(request => \&empty_json);
$integration->mock(perform_request => \&empty_json);


subtest "get service requests populates supersedes field correctly" => sub {
    my $supersedes_defect_number = 1337;
    $integration->mock(perform_request_graphql => sub {
        my ( $self, %args ) = @_;

        $args{type} ||= '';

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
                            supersedesDefectNumber => $supersedes_defect_number,
                        }
                    ]
                }
            };
        } elsif ( $args{type}  eq 'defect_types' ) {
            return {
                data => {
                    defectTypes => [
                        { code => 'SLDA', name => 'Defective Street Light' },
                    ],
                },
            }
        }

        return {};
    });

    my $res = $endpoint->run_test_request(
        GET => '/requests.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );

    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<supersedes>DEFECT_1337</supersedes>';

    $supersedes_defect_number = undef;
    $res = $endpoint->run_test_request(
        GET => '/requests.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    lacks_string $res->content, '<supersedes>';

    $integration->unmock('perform_request_graphql');
};


subtest "get service request updates populates supersedes field correctly" => sub {
    my $supersedes_defect_number = 1337;
    $integration->mock(perform_request_graphql => sub {
        return {
            data => {
                jobStatusLogs => [
                    {
                        loggedDate => '2025-01-01T00:00:00Z',
                        statusCode => 'FIXED',
                        key => 'key',
                        job => {
                            defects => [
                                {
                                    supersedesDefectNumber => $supersedes_defect_number,
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

    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );

    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<supersedes>DEFECT_1337</supersedes>';

    $supersedes_defect_number = undef;
    $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    lacks_string $res->content, '<supersedes>';

    $integration->unmock('perform_request_graphql');
};

subtest "get service requests populates priority field correctly" => sub {
    $integration->mock(perform_request_graphql => sub {
        my ( $self, %args ) = @_;

        $args{type} ||= '';

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
                            priorityCode => 'DP',
                        }
                    ]
                }
            };
        } elsif ( $args{type}  eq 'defect_types' ) {
            return {
                data => {
                    defectTypes => [
                        { code => 'SLDA', name => 'Defective Street Light' },
                    ],
                },
            }
        }

        return {};
    });

    my $res = $endpoint->run_test_request(
        GET => '/requests.xml?start_date=2025-01-01T00:00:00Z&end_date=2025-01-01T01:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<priority>DP</priority>';
    $integration->unmock('perform_request_graphql');
};

done_testing;
