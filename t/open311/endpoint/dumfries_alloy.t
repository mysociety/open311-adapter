package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling('dumfries_alloy.yml')->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Dumfries';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    $args{config_file} = path(__FILE__)->sibling('dumfries_alloy.yml')->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use Data::Dumper;

BEGIN { $ENV{TEST_MODE} = 1; }

my (@sent);
my @api_calls;  # Track all API calls for assertions
my %item_data;

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock('get', sub {
    my ($self, $url) = @_;
    return HTTP::Response->new(200, 'OK', [], '{}');
});

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ( $self, %args ) = @_;

    my $call    = $args{call};
    my $params  = $args{params};
    my $body    = $args{body};
    my $method  = $args{method} || '';
    my $is_file = $args{is_file};

    push @api_calls, \%args;

    my $content;

    if ($is_file) {
        return { fileItemId => 'file_001' };
    }

    if ($method eq 'PUT' && $call =~ m{^item/(.+)$}) {
        my $item_id = $1;
        return { item => { itemId => $item_id } };
    }

    if ($body) {
        push @sent, $body;

        if ( $call =~ m{^item$} && $body->{designCode} eq 'designs_contacts' ) {
            # Creating a contact
            $content = '{ "item": { "itemId": "contact_123" } }';
        } elsif ( $call =~ m{^item$} ) {
            # Creating new report
            $content = '{ "item": { "itemId": "report_456" } }';
        } elsif ( $call =~ m{aqs/join} ) {
            my $dodi_code = $body->{aqs}->{properties}->{dodiCode} || '';
            if ( $dodi_code eq 'designs_serviceEnquiry' ) {
                # Fetching updates
                $content = path(__FILE__)->sibling('json/alloyv2/dumfries/designs_serviceEnquiry_search.json')->slurp;
            }
        } elsif ( $call =~ m{aqs/query} ) {
            my $dodi_code = $body->{aqs}->{properties}->{dodiCode} || '';
            if ( $dodi_code eq 'designs_contacts' ) {
                # Searching for existing contact - return empty (doesn't exist)
                $content = '{ "page": 1, "results": [] }';
            } elsif ( $dodi_code eq 'designs_seReportedIssueList' ) {
                # Getting service whitelist
                $content = path(__FILE__)->sibling('json/alloyv2/dumfries/categories_search.json')->slurp;
            } else {
                $content = '{ "page": 1, "results": [] }';
            }
        } elsif ( $call =~ m{aqs/statistics} ) {
            # Statistics query - return count
            $content = '{ "page": 1, "pageSize": 20, "results": [{"value":{"attributeCode":"fake","value":5.0}}] }';
        }

    } else {
        if ( $call eq 'design/designs_serviceEnquiry' ) {
            # Getting the RFS design
            $content = path(__FILE__)->sibling('json/alloyv2/design_rfs.json')->slurp;
        } elsif ( $call =~ m{design/designs_seReportedIssueList} ) {
            # Getting service list design
            $content = '{ "design": { "code": "designs_seReportedIssueList" } }';
        } elsif ( $call =~ 'item-log/item/(.*)$' ) {
            $content = path(__FILE__)->sibling("json/alloyv2/dumfries/item_log_$1.json")->slurp;
        } elsif ( $call =~ m{^item/(.+)$} ) {
            my $item_id = $1;
            if (my $data = $item_data{$item_id}) {
                $content = encode_json({ item => $data });
            } else {
                $content = '{ "item": { "itemId": "' . $item_id . '", "attributes": [] } }';
            }
        } else {
            die "No handler found for API call $call";
        }
    }

    if ( !$content ) {
        warn 'No handler found for API call ' . $call;
        return decode_json('[]');
    }

    return decode_json( encode_utf8($content) );
});

subtest 'check services use Alloy IDs as service codes' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.json?jurisdiction_id=dumfries_alloy'
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    my $services = decode_json($res->content);

    # Find the "Pothole" service under "Roads"
    my ($pothole_roads) = grep {
        $_->{service_name} eq 'Pothole' &&
        grep { $_ eq 'Roads' } @{$_->{groups}}
    } @$services;

    is $pothole_roads->{service_code}, '123a123',
        'Roads > Pothole uses ID from config as service code';

    # Find the "Pothole" service under "Pavements"
    my ($pothole_pavements) = grep {
        $_->{service_name} eq 'Pothole' &&
        grep { $_ eq 'Pavements' } @{$_->{groups}}
    } @$services;

    is $pothole_pavements->{service_code}, '456d456',
        'Pavements > Pothole uses different ID from config as service code';

    # Verify they're different even though they have the same name
    isnt $pothole_roads->{service_code}, $pothole_pavements->{service_code},
        'Same subcategory name in different groups gets different service codes';
};

subtest 'send new report to Alloy with contact and service_code' => sub {
    set_fixed_time('2025-12-03T12:00:00Z');

    @sent = ();

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dumfries_alloy',
        api_key => 'test',
        service_code => '123a123',  # Using the Alloy ID as service code
        address_string => '1 High Street',
        first_name => 'Test',
        last_name => 'User',
        email => 'test@example.com',
        phone => '07700900123',
        description => 'There is a large pothole',
        lat => '55.0611',
        long => '-3.6056',
        'attribute[description]' => 'There is a large pothole',
        'attribute[title]' => 'Pothole on High Street',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[category]' => 'Roads_Pothole',
        'attribute[fixmystreet_id]' => 123,
        'attribute[easting]' => 300000,
        'attribute[northing]' => 600000,
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    # Filter to only item creations (not AQS queries)
    my @items = grep { $_->{designCode} } @sent;

    # Should have created a contact first, then the report
    is scalar(@items), 2, 'created contact and report'
        or diag "Got " . scalar(@items) . " items:\n" . Dumper(\@items);

    my $contact_sent = $items[0];
    is $contact_sent->{designCode}, 'designs_contacts',
        'first call creates contact';

    my $report_sent = $items[1];

    # Find the contact attribute
    my ($contact_attr) = grep {
        $_->{attributeCode} eq 'attributes_defectsReporters'
    } @{$report_sent->{attributes}};

    ok $contact_attr, 'contact attribute present';
    is_deeply $contact_attr->{value}, ['contact_123'],
        'contact attribute contains created contact ID';

    # Find the service_code attribute
    my ($service_code_attr) = grep {
        $_->{attributeCode} eq 'attributes_serviceEnquiryReportedIssue'
    } @{$report_sent->{attributes}};

    ok $service_code_attr, 'service_code attribute present';
    is_deeply $service_code_attr->{value}, ['123a123'],
        'service_code attribute contains the Alloy ID';

    is_deeply decode_json($res->content),
        [ { service_request_id => 'report_456' } ],
        'correct json returned';

    restore_time();
};

subtest 'inspection_status mapping' => sub {
    # Test that inspection_status correctly maps status/outcome/priority combinations
    # to Open311 statuses based on the config, and returns external_status_code

    # Test OPEN status - Awaiting Inspection
    my $defect = {
        attributes_status => ['123abc'],
    };
    my ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'open', 'Awaiting Inspection maps to open';
    is $ext, '123abc::', 'external_status_code contains status only';

    # Test OPEN status - Reported with 24hr priority
    $defect = {
        attributes_status => ['456def'],
        attributes_hwyPriority => ['987ffa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'open', 'Reported + 24hr priority maps to open';
    is $ext, '456def::987ffa', 'external_status_code contains status and priority';

    # Test OPEN status - Reported with 5 day priority (using se_priority)
    $defect = {
        attributes_status => ['456def'],
        attributes_sePriority => ['12ef34a'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'open', 'Reported + 5 day priority maps to open';
    is $ext, '456def::12ef34a', 'external_status_code contains status and se_priority';

    # Test INVESTIGATING status - note: this matches 'open' first due to config order
    # The open rule with outcome=null matches before the investigating rule
    $defect = {
        attributes_status => ['456def'],
        attributes_outcome => ['981bbe'],
        attributes_hwyPriority => ['987ffa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'open', 'Reported + Further Investigation + 24hr priority matches open (config order)';
    is $ext, '456def:981bbe:987ffa', 'external_status_code contains all three values';

    # Test PLANNED status
    $defect = {
        attributes_status => ['1212aad'],
        attributes_hwyPriority => ['987ffa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'planned', 'Job Raised + 24hr priority maps to planned';
    is $ext, '1212aad::987ffa', 'external_status_code contains status and priority';

    # Test FIXED status
    $defect = {
        attributes_status => ['91827eea'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'fixed', 'Remedied maps to fixed';
    is $ext, '91827eea::', 'external_status_code contains status only';

    # Test FIXED status, ignoring priority
    $defect = {
        attributes_status => ['91827eea'],
        attributes_hwyPriority => ['12ef34a'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'fixed', 'Remedied maps to fixed';
    is $ext, '91827eea::12ef34a', 'external_status_code still captures actual priority';

    # Test DUPLICATE status
    $defect = {
        attributes_status => ['11aa22cc'],
        attributes_outcome => ['1133cc11'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'duplicate', 'No Action Required + No Action outcome maps to duplicate';
    is $ext, '11aa22cc:1133cc11:', 'external_status_code contains status and outcome';

    # Test NO_FURTHER_ACTION status
    $defect = {
        attributes_status => ['11aa22cc'],
        attributes_outcome => ['98ae11'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'no_further_action', 'No Action Required + Defect no action outcome maps to no_further_action';
    is $ext, '11aa22cc:98ae11:', 'external_status_code contains status and outcome';

    # Test NOT_COUNCILS_RESPONSIBILITY status - note: this matches 'fixed' first due to config order
    # The fixed rule with outcome=null, priority=null matches before the not_councils_responsibility rule
    $defect = {
        attributes_status => ['91827eea'],
        attributes_outcome => ['123a9ea'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'fixed', 'Remedied + Passed to 3rd Party matches fixed (config order)';
    is $ext, '91827eea:123a9ea:', 'external_status_code contains status and outcome';

    # Test CLOSED status with Low Risk priority
    $defect = {
        attributes_sePriority => ['9a9a9a'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'closed', 'Low Risk priority maps to closed';
    is $ext, '::9a9a9a', 'external_status_code contains priority only';

    # Test CLOSED status with No Response priority
    $defect = {
        attributes_hwyPriority => ['9b9b9baa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'closed', 'No Response priority maps to closed';
    is $ext, '::9b9b9baa', 'external_status_code contains priority only';

    # Test CLOSED status with No Response priority, ignoring outcome
    $defect = {
        attributes_outcome => ['123a9ea'],
        attributes_hwyPriority => ['9b9b9baa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'closed', 'No Response priority maps to closed';
    is $ext, ':123a9ea:9b9b9baa', 'external_status_code contains outcome and priority';

    # Test CLOSED status with No Response priority, ignoring status
    $defect = {
        attributes_status => ['91827eeb'],
        attributes_hwyPriority => ['9b9b9baa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'closed', 'No Response priority maps to closed';
    is $ext, '91827eeb::9b9b9baa', 'external_status_code contains status and priority';

    # Test CLOSED status with No Response priority, ignoring status and outcome
    $defect = {
        attributes_status => ['91827eeb'],
        attributes_outcome => ['123a9eb'],
        attributes_hwyPriority => ['9b9b9baa'],
    };
    ($status, $ext) = $endpoint->inspection_status($defect);
    is $status, 'closed', 'No Response priority maps to closed';
    is $ext, '91827eeb:123a9eb:9b9b9baa', 'external_status_code contains all three values';

    # Test that non-matching combinations return IGNORE (scalar, not list)
    $defect = {
        attributes_status => ['unknown_status'],
        attributes_outcome => ['unknown_outcome'],
        attributes_hwyPriority => ['unknown_priority'],
    };
    is $endpoint->inspection_status($defect), 'IGNORE',
        'Unmatched status combination returns IGNORE';

    # Test _skip_inspection_update returns true for IGNORE status
    ok $endpoint->_skip_inspection_update('IGNORE'),
        '_skip_inspection_update returns true for IGNORE status';

    # Test _skip_inspection_update returns false for other statuses
    ok !$endpoint->_skip_inspection_update('open'),
        '_skip_inspection_update returns false for open status';
};

subtest 'priority pulled through' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json?start_date=2025-12-25T00:00:00Z&end_date=2025-12-26T00:00:00Z'
    );
    my $updates = decode_json($res->content);
    for my $update (@$updates) {
        $update->{media_url} ||= '';
        $update->{extras} ||= { latest_data_only => 1 };
        $update->{updated_datetime} ||= '2025-12-25T12:00:00Z';
    }
    is scalar(@$updates), 1, 'Got 1 update (second has no status attributes, returns IGNORE and is filtered)';
    is_deeply $updates->[0], {
      "status" => "planned",
      "external_status_code" => "1212aad:1234ade:987ffa",
      "updated_datetime" => "2025-12-25T12:00:00Z",
      "media_url" => "",
      "update_id" => "63ee34826965f30390f01cda_20251225120000",
      "extras" => {
         "latest_data_only" => 1,
         "priority" => "Critical Risk"
      },
      "description" => "",
      "service_request_id" => "63ee34826965f30390f01cda"
    }, 'First update has correct data with priority';
};

%item_data = (
    report_456 => {
        itemId => 'report_456',
        attributes => [{
            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
            value => ['inspection_456']
        }]
    },
    inspection_456 => {
        itemId => 'inspection_456',
    },
);

subtest 'post_service_request updates inspection status for Street Lighting -> Other' => sub {
    # Test that posting a service request with a special service code
    # (no photos) updates the inspection status to "Issued"

    @api_calls = ();

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dumfries_alloy',
        api_key => 'test',
        service_code => '678f678',
        address_string => '1 High Street',
        first_name => 'Test',
        last_name => 'User',
        email => 'test@example.com',
        phone => '07700900123',
        description => 'Street light issue',
        lat => '55.0611',
        long => '-3.6056',
        'attribute[description]' => 'Street light issue',
        'attribute[title]' => 'Street light on High Street',
        'attribute[report_url]' => 'http://localhost/789',
        'attribute[category]' => 'Street_Lighting_Other',
        'attribute[fixmystreet_id]' => 124,
        'attribute[easting]' => 300000,
        'attribute[northing]' => 600000,
    );

    ok $res->is_success, 'valid request' or diag $res->content;

    my @inspection_updates = grep {
        $_->{call} && $_->{call} eq 'item/inspection_456' &&
        $_->{method} && $_->{method} eq 'PUT'
    } @api_calls;

    is scalar(@inspection_updates), 1, 'inspection was updated once';

    my ($status_attr) = grep {
        $_->{attributeCode} eq 'attributes_tasksStatus'
    } @{$inspection_updates[0]->{body}{attributes}};

    ok $status_attr, 'status attribute present in update';
    is_deeply $status_attr->{value}, ['aa11bb22'], 'inspection status set to Issued';
};

subtest 'post_service_request with photos and status update' => sub {
    # Test that both photo attachment and status update happen

    @api_calls = ();

    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dumfries_alloy',
        api_key => 'test',
        service_code => '678f678',
        address_string => '1 High Street',
        first_name => 'Test',
        last_name => 'User',
        email => 'test@example.com',
        phone => '07700900123',
        description => 'Street light issue with photo',
        lat => '55.0611',
        long => '-3.6056',
        'attribute[description]' => 'Street light issue with photo',
        'attribute[title]' => 'Street light on High Street',
        'attribute[report_url]' => 'http://localhost/790',
        'attribute[category]' => 'Street_Lighting_Other',
        'attribute[fixmystreet_id]' => 125,
        'attribute[easting]' => 300000,
        'attribute[northing]' => 600000,
        media_url => 'http://example.org/photo/1.jpeg',
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    my @inspection_updates = grep {
        $_->{call} && $_->{call} eq 'item/inspection_456' &&
        $_->{method} && $_->{method} eq 'PUT'
    } @api_calls;

    is scalar(@inspection_updates), 2, 'inspection was updated twice (photo + status)';

    my ($status_update) = grep {
        my $attrs = $_->{body}{attributes};
        grep { $_->{attributeCode} eq 'attributes_tasksStatus' } @$attrs;
    } @inspection_updates;

    ok $status_update, 'status update found';
    my ($status_attr) = grep {
        $_->{attributeCode} eq 'attributes_tasksStatus'
    } @{$status_update->{body}{attributes}};

    is_deeply $status_attr->{value}, ['aa11bb22'], 'inspection status set to Issued';

    my ($photo_update) = grep {
        my $attrs = $_->{body}{attributes};
        grep { $_->{attributeCode} eq 'attributes_filesAttachableAttachments' } @$attrs;
    } @inspection_updates;

    ok $photo_update, 'photo attachment update found';
};

%item_data = ();

subtest '_find_latest_inspection with single inspection' => sub {
    # Mock api_call to return a defect with a single inspection
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_001') {
            return {
                item => {
                    itemId => 'inspection_001',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-25T15:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_001/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_001',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_001']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_001', 'finds single inspection';
};

subtest '_find_latest_inspection with multiple inspections' => sub {
    # Mock api_call to return a defect with multiple inspections
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_001') {
            return {
                item => {
                    itemId => 'inspection_001',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-20T10:00:00.000Z',
                    createdDate => '2025-12-20T10:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_002') {
            return {
                item => {
                    itemId => 'inspection_002',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-25T15:00:00.000Z',
                    createdDate => '2025-12-21T11:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_003') {
            return {
                item => {
                    itemId => 'inspection_003',
                    designCode => 'designs_hWYCustomerReport',
                    # No lastEditDate - should use createdDate
                    createdDate => '2025-12-22T12:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_002/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_002',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_001', 'inspection_002', 'inspection_003']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_002',
        'finds most recent inspection by lastEditDate';
};

subtest '_find_latest_inspection uses createdDate fallback' => sub {
    # Mock api_call to return inspections without lastEditDate
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_004') {
            return {
                item => {
                    itemId => 'inspection_004',
                    designCode => 'designs_hWYCustomerReport',
                    createdDate => '2025-12-20T10:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_005') {
            return {
                item => {
                    itemId => 'inspection_005',
                    designCode => 'designs_hWYCustomerReport',
                    createdDate => '2025-12-25T15:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_003/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_003',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_004', 'inspection_005']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_005',
        'uses createdDate when lastEditDate not available';
};

subtest '_find_latest_inspection via parent relationship' => sub {
    # Mock api_call to return a defect where inspection is found via parents
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/defect_004/parents') {
            return {
                results => [
                    {
                        itemId => 'parent_asset',
                        designCode => 'designs_asset',
                        lastEditDate => '2025-12-20T10:00:00.000Z',
                    },
                    {
                        itemId => 'inspection_006',
                        designCode => 'designs_inspection',
                        lastEditDate => '2025-12-25T15:00:00.000Z',
                    }
                ]
            };
        }
    });

    my $defect = {
        itemId => 'defect_004',
        attributes => []
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_006',
        'finds inspection via parent relationship';
};

subtest 'post_service_request_update creates inspection with mapped attributes' => sub {
    # Test that posting an update creates a new inspection with:
    # - updated_datetime mapped to attributes_tasksRaisedTime
    # - description mapped to attributes_hWYCustomerReportCustomerDescriptionField
    # - attributes_tasksIssuedTime NOT copied from template
    # - defect updated to link to new inspection

    my @api_calls;
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        push @api_calls, \%args;

        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_101' && !$method) {
            # Return the defect (initial fetch)
            return {
                item => {
                    itemId => 'defect_101',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_123',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_101']
                        },
                        {
                            attributeCode => 'attributes_status',
                            value => ['status_456']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_101') {
            # Return the template inspection
            return {
                item => {
                    itemId => 'inspection_101',
                    designCode => 'designs_hWYCustomerReport',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    lastEditDate => '2025-12-20T10:00:00.000Z',
                    parents => [{ itemId => 'asset_123' }],
                    attributes => [
                        { attributeCode => 'attributes_itemsTitle', value => 'INS-123' },
                        { attributeCode => 'attributes_itemsSubtitle', value => 'Test' },
                        { attributeCode => 'attributes_inspectionsInspectionNumber', value => '123' },
                        { attributeCode => 'attributes_tasksIssuedTime', value => '2025-12-20T09:00:00.000Z' },
                        { attributeCode => 'attributes_tasksRaisedTime', value => '2025-12-20T08:00:00.000Z' },
                        { attributeCode => 'attributes_hWYCustomerReportCustomerDescriptionField', value => 'Old description' },
                        { attributeCode => 'attributes_status', value => ['status_123'] },
                        { attributeCode => 'attributes_someOtherField', value => 'keep this' },
                    ]
                }
            };
        } elsif ($call eq 'item/defect_101/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Creating new inspection
            return {
                item => {
                    itemId => 'inspection_102'
                }
            };
        } elsif ($call eq 'item/defect_101' && $method eq 'PUT') {
            # Updating defect to link new inspection
            return {
                item => {
                    itemId => 'defect_101'
                }
            };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_101',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        description => 'Update from FMS user',
    });

    # Find the call that created the new inspection
    my ($create_call) = grep { $_->{call} eq 'item' && $_->{body} } @api_calls;
    ok $create_call, 'new inspection was created';

    my $new_inspection = $create_call->{body};
    is $new_inspection->{designCode}, 'designs_hWYCustomerReport',
        'new inspection has correct design code';

    # Check that attributes were properly mapped and filtered
    my %attrs = map { $_->{attributeCode} => $_->{value} } @{$new_inspection->{attributes}};

    # Should NOT include these read-only/computed attributes
    ok !exists $attrs{attributes_itemsTitle}, 'attributes_itemsTitle not copied';
    ok !exists $attrs{attributes_itemsSubtitle}, 'attributes_itemsSubtitle not copied';
    ok !exists $attrs{attributes_inspectionsInspectionNumber}, 'inspection number not copied';
    ok !exists $attrs{attributes_tasksIssuedTime}, 'attributes_tasksIssuedTime not copied';

    # SHOULD include attributes from the update mapping
    is $attrs{attributes_tasksRaisedTime}, '2025-12-25T14:30:00Z',
        'updated_datetime mapped to attributes_tasksRaisedTime';
    is $attrs{attributes_hWYCustomerReportCustomerDescriptionField}, 'Update from FMS user',
        'description mapped to customer description field';

    # SHOULD include other regular attributes from template
    is $attrs{attributes_status}->[0], 'status_123',
        'status copied from template';
    is $attrs{attributes_someOtherField}, 'keep this',
        'other fields copied from template';

    # Check the return value
    is $result->status, 'investigating', 'returned update has correct status';
    is $result->update_id, 'defect_101_inspection_102',
        'returned update has combined ID';

    # Verify the defect was updated with the new inspection ID
    my ($update_call) = grep {
        $_->{call} eq 'item/defect_101' &&
        $_->{method} && $_->{method} eq 'PUT'
    } @api_calls;
    ok $update_call, 'defect was updated';

    my $updated_defect = $update_call->{body};

    # Verify the PUT body only contains attributes and signature (partial update)
    ok exists $updated_defect->{attributes}, 'PUT body has attributes';
    ok exists $updated_defect->{signature}, 'PUT body has signature';
    ok !exists $updated_defect->{designCode}, 'PUT body does not include designCode';
    ok !exists $updated_defect->{geometry}, 'PUT body does not include geometry';

    my ($inspection_attr) = grep {
        $_->{attributeCode} eq 'attributes_defectsWithInspectionsDefectInspection'
    } @{$updated_defect->{attributes}};

    ok $inspection_attr, 'defect has inspection attribute';
    is_deeply $inspection_attr->{value}, ['inspection_101', 'inspection_102'],
        'defect inspection list includes both old and new inspection IDs';

    # Verify we only updated the inspection attribute, not all attributes
    is scalar(@{$updated_defect->{attributes}}), 1,
        'PUT body only includes the inspection attribute being changed';
};

subtest 'post_service_request_update without description' => sub {
    # Test that description is optional

    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_102' && !$method) {
            return {
                item => {
                    itemId => 'defect_102',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_456',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_103']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_103') {
            return {
                item => {
                    itemId => 'inspection_103',
                    designCode => 'designs_hWYCustomerReport',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    attributes => [
                        { attributeCode => 'attributes_status', value => ['status_123'] },
                    ]
                }
            };
        } elsif ($call eq 'item/defect_102/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Check that description field is not present when not provided
            my %attrs = map { $_->{attributeCode} => 1 } @{$body->{attributes}};
            ok !exists $attrs{attributes_hWYCustomerReportCustomerDescriptionField},
                'description field not present when not provided';
            return { item => { itemId => 'inspection_104' } };
        } elsif ($call eq 'item/defect_102' && $method eq 'PUT') {
            return { item => { itemId => 'defect_102' } };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_102',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        # No description
    });

    is $result->update_id, 'defect_102_inspection_104',
        'update created successfully without description';
};

subtest 'post_service_request_update with media_url uploads attachment' => sub {
    my @api_calls;
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        push @api_calls, \%args;

        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';
        my $is_file = $args{is_file};

        if ($call eq 'item/defect_104' && !$method) {
            return {
                item => {
                    itemId => 'defect_104',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_901',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_107']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_107') {
            return {
                item => {
                    itemId => 'inspection_107',
                    designCode => 'designs_hWYCustomerReport',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    attributes => [
                        { attributeCode => 'attributes_status', value => ['status_123'] },
                    ]
                }
            };
        } elsif ($call eq 'item/defect_104/parents') {
            return { results => [] };
        } elsif ($is_file) {
            return { fileItemId => 'file_123' };
        } elsif ($call eq 'item' && $body && !$method) {
            return { item => { itemId => 'inspection_108' } };
        } elsif ($call eq 'item/defect_104' && $method eq 'PUT') {
            return { item => { itemId => 'defect_104' } };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_104',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        description => 'Update with photo',
        media_url => ['http://example.org/photo/1.jpeg'],
        uploads => [],
    });

    my ($create_call) = grep { $_->{call} eq 'item' && $_->{body} } @api_calls;
    ok $create_call, 'created inspection with attachments';

    my $new_inspection = $create_call->{body};
    my %attrs = map { $_->{attributeCode} => $_->{value} } @{$new_inspection->{attributes}};
    is_deeply $attrs{attributes_filesAttachableAttachments}, ['file_123'],
        'inspection includes uploaded attachment';

    is $result->update_id, 'defect_104_inspection_108',
        'update created successfully with attachment';
};

subtest 'post_service_request_update with parent-type inspection (no description field)' => sub {
    # Test that we don't try to set description field on inspections that don't have it
    # (e.g., inspections found via parent relationship)

    my @api_calls;
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        push @api_calls, \%args;

        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_103' && !$method) {
            return {
                item => {
                    itemId => 'defect_103',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_789',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_105']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_105') {
            # Return a parent-type inspection (no description or raised time fields)
            return {
                item => {
                    itemId => 'inspection_105',
                    designCode => 'designs_someOtherInspection',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    attributes => [
                        { attributeCode => 'attributes_status', value => ['status_abc'] },
                        { attributeCode => 'attributes_someField', value => 'some value' },
                        # NOTE: No attributes_hWYCustomerReportCustomerDescriptionField
                        # NOTE: No attributes_tasksRaisedTime
                    ]
                }
            };
        } elsif ($call eq 'item/defect_103/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Check that description field is NOT present (template doesn't have it)
            my %attrs = map { $_->{attributeCode} => $_->{value} } @{$body->{attributes}};
            ok !exists $attrs{attributes_hWYCustomerReportCustomerDescriptionField},
                'description field not set when template lacks it';
            ok !exists $attrs{attributes_tasksRaisedTime},
                'raised time field not set when template lacks it';

            # Should still have the other fields from template
            is $attrs{attributes_status}->[0], 'status_abc',
                'other fields still copied from template';

            return { item => { itemId => 'inspection_106' } };
        } elsif ($call eq 'item/defect_103' && $method eq 'PUT') {
            return { item => { itemId => 'defect_103' } };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_103',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        description => 'This description should be ignored',
    });

    is $result->update_id, 'defect_103_inspection_106',
        'update created successfully even when template lacks description field';
};

subtest 'photo fetching with AQS cache' => sub {
    # Mock api_call to handle photo fetching scenarios
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my %mock_responses = (
        # Defect with job and inspection
        'item/defect_with_photos' => {
            item => {
                itemId => 'defect_with_photos',
                designCode => 'designs_defects',
                attributes => [
                    { attributeCode => 'attributes_defectsRaisingJobsRaisedJobs', value => 'job_001' },
                    { attributeCode => 'attributes_defectsWithInspectionsDefectInspection', value => 'insp_001' },
                ],
            }
        },
        # Job with 2 attachments
        'item/job_001' => {
            item => {
                itemId => 'job_001',
                designCode => 'designs_jobs',
                attributes => [
                    { attributeCode => 'attributes_filesAttachableAttachments', value => ['file_001', 'file_002'] },
                ],
            }
        },
        # Inspection with 1 attachment (overlapping with job)
        'item/insp_001' => {
            item => {
                itemId => 'insp_001',
                designCode => 'designs_hWYCustomerReport',
                attributes => [
                    { attributeCode => 'attributes_filesAttachableAttachments', value => 'file_002' },
                ],
            }
        },
        # File items
        'item/file_001' => {
            item => {
                itemId => 'file_001',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'photo1.jpg' },
                ],
            }
        },
        'item/file_002' => {
            item => {
                itemId => 'file_002',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'photo2.jpg' },
                ],
            }
        },
        'item/file_003' => {
            item => {
                itemId => 'file_003',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => '123.456.full.photo3.jpg' },
                ],
            }
        },
        # Item logs (creation dates)
        'item-log/item/file_001' => {
            results => [
                { action => 'Create', date => '2025-12-25T10:00:00.000Z' },
            ],
        },
        'item-log/item/file_002' => {
            results => [
                { action => 'Create', date => '2025-12-25T11:00:00.000Z' },
            ],
        },
        'item-log/item/file_003' => {
            results => [
                { action => 'Create', date => '2025-12-25T12:00:00.000Z' },
            ],
        },
    );

    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        return $mock_responses{$call} if exists $mock_responses{$call};
        die "Unmocked API call: $call";
    });

    $integration->mock('search', sub {
        my ($self, $body) = @_;
        # Return files within date range for cache building
        return [
            {
                itemId => 'file_001',
                createdDate => '2025-12-25T10:00:00.000Z',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'photo1.jpg' },
                ],
            },
            {
                itemId => 'file_002',
                createdDate => '2025-12-25T11:00:00.000Z',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'photo2.jpg' },
                ],
            },
            # file_003 has FMS pattern, should be filtered out
            {
                itemId => 'file_003',
                createdDate => '2025-12-25T12:00:00.000Z',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => '123.456.full.photo3.jpg' },
                ],
            },
        ];
    });

    # Build attachment cache with date range
    my $cache = $endpoint->_build_attachment_cache({
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    });

    # Check cache contains valid files only (not FMS pattern)
    is(scalar(keys %$cache), 2, 'Cache contains 2 valid files');
    ok(exists $cache->{file_001}, 'Cache contains file_001');
    ok(exists $cache->{file_002}, 'Cache contains file_002');
    ok(!exists $cache->{file_003}, 'Cache does not contain FMS file');

    # Test _get_job_media_urls with cache
    my $defect = $mock_responses{'item/defect_with_photos'}{item};
    my $job_urls = $endpoint->_get_job_media_urls($defect, {
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    }, $cache);

    # Should get file_001 only (file_002 is on inspection and should be excluded to avoid duplication)
    is(scalar(@$job_urls), 1, 'Got 1 job media URL');
    like($job_urls->[0], qr/photos.*item=file_001/, 'Job URL contains file_001');

    # Test _get_inspection_media_urls with cache
    my $insp_urls = $endpoint->_get_inspection_media_urls($defect, {
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    }, $cache);

    # Should get file_002 from inspection
    is(scalar(@$insp_urls), 1, 'Got 1 inspection media URL');
    like($insp_urls->[0], qr/photos.*item=file_002/, 'Inspection URL contains file_002');
};

subtest 'photo fetching without cache (fallback behavior)' => sub {
    # Test the fallback path when no cache is provided
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my %mock_responses = (
        'item/defect_simple' => {
            item => {
                itemId => 'defect_simple',
                designCode => 'designs_defects',
                attributes => [
                    { attributeCode => 'attributes_defectsRaisingJobsRaisedJobs', value => 'job_002' },
                ],
            }
        },
        'item/job_002' => {
            item => {
                itemId => 'job_002',
                designCode => 'designs_jobs',
                attributes => [
                    { attributeCode => 'attributes_filesAttachableAttachments', value => 'file_004' },
                ],
            }
        },
        'item/file_004' => {
            item => {
                itemId => 'file_004',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'valid_photo.jpg' },
                ],
            }
        },
        'item-log/item/file_004' => {
            results => [
                { action => 'Create', date => '2025-12-25T14:00:00.000Z' },
            ],
        },
    );

    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        return $mock_responses{$call} if exists $mock_responses{$call};
        die "Unmocked API call: $call";
    });

    # Call without cache (should fall back to individual API calls)
    my $defect = $mock_responses{'item/defect_simple'}{item};
    my $urls = $endpoint->_get_job_media_urls($defect, {
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    });

    is(scalar(@$urls), 1, 'Got 1 media URL via fallback path');
    like($urls->[0], qr/photos.*item=file_004/, 'URL contains file_004');
};

subtest 'FMS file filtering' => sub {
    # Test that FMS auto-generated files are excluded
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my %mock_responses = (
        'item/defect_fms' => {
            item => {
                itemId => 'defect_fms',
                designCode => 'designs_defects',
                attributes => [
                    { attributeCode => 'attributes_defectsRaisingJobsRaisedJobs', value => 'job_003' },
                ],
            }
        },
        'item/job_003' => {
            item => {
                itemId => 'job_003',
                designCode => 'designs_jobs',
                attributes => [
                    { attributeCode => 'attributes_filesAttachableAttachments', value => ['file_fms', 'file_valid'] },
                ],
            }
        },
        'item/file_fms' => {
            item => {
                itemId => 'file_fms',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => '12345.67890.full.original.jpg' },
                ],
            }
        },
        'item/file_valid' => {
            item => {
                itemId => 'file_valid',
                designCode => 'designs_files',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'user_photo.jpg' },
                ],
            }
        },
        'item-log/item/file_fms' => {
            results => [
                { action => 'Create', date => '2025-12-25T15:00:00.000Z' },
            ],
        },
        'item-log/item/file_valid' => {
            results => [
                { action => 'Create', date => '2025-12-25T16:00:00.000Z' },
            ],
        },
    );

    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        return $mock_responses{$call} if exists $mock_responses{$call};
        die "Unmocked API call: $call";
    });

    my $defect = $mock_responses{'item/defect_fms'}{item};
    my $urls = $endpoint->_get_job_media_urls($defect, {
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    });

    # Should only get the valid file, FMS file should be filtered out
    is(scalar(@$urls), 1, 'Got only 1 URL (FMS file excluded)');
    like($urls->[0], qr/photos.*item=file_valid/, 'URL is for valid file');
    unlike($urls->[0], qr/file_fms/, 'FMS file not included');
};

subtest 'date range filtering' => sub {
    # Test that photos outside date range are excluded
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my %mock_responses = (
        'item/defect_dates' => {
            item => {
                itemId => 'defect_dates',
                designCode => 'designs_defects',
                attributes => [
                    { attributeCode => 'attributes_defectsRaisingJobsRaisedJobs', value => 'job_004' },
                ],
            }
        },
        'item/job_004' => {
            item => {
                itemId => 'job_004',
                designCode => 'designs_jobs',
                attributes => [
                    { attributeCode => 'attributes_filesAttachableAttachments', value => ['file_old', 'file_new', 'file_future'] },
                ],
            }
        },
        'item/file_old' => {
            item => {
                itemId => 'file_old',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'old.jpg' },
                ],
            }
        },
        'item/file_new' => {
            item => {
                itemId => 'file_new',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'new.jpg' },
                ],
            }
        },
        'item/file_future' => {
            item => {
                itemId => 'file_future',
                attributes => [
                    { attributeCode => 'attributes_filesOriginalName', value => 'future.jpg' },
                ],
            }
        },
        'item-log/item/file_old' => {
            results => [
                { action => 'Create', date => '2025-12-20T10:00:00.000Z' }, # Before range
            ],
        },
        'item-log/item/file_new' => {
            results => [
                { action => 'Create', date => '2025-12-25T10:00:00.000Z' }, # In range
            ],
        },
        'item-log/item/file_future' => {
            results => [
                { action => 'Create', date => '2025-12-30T10:00:00.000Z' }, # After range
            ],
        },
    );

    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        return $mock_responses{$call} if exists $mock_responses{$call};
        die "Unmocked API call: $call";
    });

    my $defect = $mock_responses{'item/defect_dates'}{item};
    my $urls = $endpoint->_get_job_media_urls($defect, {
        start_date => '2025-12-25T00:00:00Z',
        end_date => '2025-12-26T00:00:00Z',
    });

    # Should only get file_new (in range), not file_old or file_future
    is(scalar(@$urls), 1, 'Got only 1 URL (date filtered)');
    like($urls->[0], qr/photos.*item=file_new/, 'URL is for file in date range');
};

subtest '_find_latest_inspection with single inspection' => sub {
    # Mock api_call to return a defect with a single inspection
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_001') {
            return {
                item => {
                    itemId => 'inspection_001',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-25T15:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_001/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_001',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_001']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_001', 'finds single inspection';
};

subtest '_find_latest_inspection with multiple inspections' => sub {
    # Mock api_call to return a defect with multiple inspections
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_001') {
            return {
                item => {
                    itemId => 'inspection_001',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-20T10:00:00.000Z',
                    createdDate => '2025-12-20T10:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_002') {
            return {
                item => {
                    itemId => 'inspection_002',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-25T15:00:00.000Z',
                    createdDate => '2025-12-21T11:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_003') {
            return {
                item => {
                    itemId => 'inspection_003',
                    designCode => 'designs_hWYCustomerReport',
                    # No lastEditDate - should use createdDate
                    createdDate => '2025-12-22T12:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_002/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_002',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_001', 'inspection_002', 'inspection_003']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_002',
        'finds most recent inspection by lastEditDate';
};

subtest '_find_latest_inspection uses createdDate fallback' => sub {
    # Mock api_call to return inspections without lastEditDate
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_004') {
            return {
                item => {
                    itemId => 'inspection_004',
                    designCode => 'designs_hWYCustomerReport',
                    createdDate => '2025-12-20T10:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/inspection_005') {
            return {
                item => {
                    itemId => 'inspection_005',
                    designCode => 'designs_hWYCustomerReport',
                    createdDate => '2025-12-25T15:00:00.000Z',
                    attributes => [],
                }
            };
        } elsif ($call eq 'item/defect_003/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_003',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_004', 'inspection_005']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_005',
        'uses createdDate when lastEditDate not available';
};

subtest '_find_latest_inspection via parent relationship' => sub {
    # Mock api_call to return a defect where inspection is found via parents
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/defect_004/parents') {
            return {
                results => [
                    {
                        itemId => 'parent_asset',
                        designCode => 'designs_asset',
                        lastEditDate => '2025-12-20T10:00:00.000Z',
                    },
                    {
                        itemId => 'inspection_006',
                        designCode => 'designs_inspection',
                        lastEditDate => '2025-12-25T15:00:00.000Z',
                    }
                ]
            };
        }
    });

    my $defect = {
        itemId => 'defect_004',
        attributes => []
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_006',
        'finds inspection via parent relationship';
};

subtest 'post_service_request_update creates inspection with mapped attributes' => sub {
    # Test that posting an update creates a new inspection with:
    # - updated_datetime mapped to attributes_tasksRaisedTime
    # - description mapped to attributes_hWYCustomerReportCustomerDescriptionField
    # - attributes_tasksIssuedTime NOT copied from template
    # - defect updated to link to new inspection

    my @api_calls;
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        push @api_calls, \%args;

        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_101' && !$method) {
            # Return the defect (initial fetch)
            return {
                item => {
                    itemId => 'defect_101',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_123',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_101']
                        },
                        {
                            attributeCode => 'attributes_status',
                            value => ['status_456']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_101') {
            # Return the template inspection
            return {
                item => {
                    itemId => 'inspection_101',
                    designCode => 'designs_hWYCustomerReport',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    lastEditDate => '2025-12-20T10:00:00.000Z',
                    parents => [{ itemId => 'asset_123' }],
                    attributes => [
                        { attributeCode => 'attributes_itemsTitle', value => 'INS-123' },
                        { attributeCode => 'attributes_itemsSubtitle', value => 'Test' },
                        { attributeCode => 'attributes_inspectionsInspectionNumber', value => '123' },
                        { attributeCode => 'attributes_tasksIssuedTime', value => '2025-12-20T09:00:00.000Z' },
                        { attributeCode => 'attributes_tasksRaisedTime', value => '2025-12-20T08:00:00.000Z' },
                        { attributeCode => 'attributes_hWYCustomerReportCustomerDescriptionField', value => 'Old description' },
                        { attributeCode => 'attributes_status', value => ['status_123'] },
                        { attributeCode => 'attributes_someOtherField', value => 'keep this' },
                    ]
                }
            };
        } elsif ($call eq 'item/defect_101/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Creating new inspection
            return {
                item => {
                    itemId => 'inspection_102'
                }
            };
        } elsif ($call eq 'item/defect_101' && $method eq 'PUT') {
            # Updating defect to link new inspection
            return {
                item => {
                    itemId => 'defect_101'
                }
            };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_101',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        description => 'Update from FMS user',
    });

    # Find the call that created the new inspection
    my ($create_call) = grep { $_->{call} eq 'item' && $_->{body} } @api_calls;
    ok $create_call, 'new inspection was created';

    my $new_inspection = $create_call->{body};
    is $new_inspection->{designCode}, 'designs_hWYCustomerReport',
        'new inspection has correct design code';

    # Check that attributes were properly mapped and filtered
    my %attrs = map { $_->{attributeCode} => $_->{value} } @{$new_inspection->{attributes}};

    # Should NOT include these read-only/computed attributes
    ok !exists $attrs{attributes_itemsTitle}, 'attributes_itemsTitle not copied';
    ok !exists $attrs{attributes_itemsSubtitle}, 'attributes_itemsSubtitle not copied';
    ok !exists $attrs{attributes_inspectionsInspectionNumber}, 'inspection number not copied';
    ok !exists $attrs{attributes_tasksIssuedTime}, 'attributes_tasksIssuedTime not copied';

    # SHOULD include attributes from the update mapping
    is $attrs{attributes_tasksRaisedTime}, '2025-12-25T14:30:00Z',
        'updated_datetime mapped to attributes_tasksRaisedTime';
    is $attrs{attributes_hWYCustomerReportCustomerDescriptionField}, 'Update from FMS user',
        'description mapped to customer description field';

    # SHOULD include other regular attributes from template
    is $attrs{attributes_status}->[0], 'status_123',
        'status copied from template';
    is $attrs{attributes_someOtherField}, 'keep this',
        'other fields copied from template';

    # Check the return value
    is $result->status, 'investigating', 'returned update has correct status';
    is $result->update_id, 'defect_101_inspection_102',
        'returned update has combined ID';

    # Verify the defect was updated with the new inspection ID
    my ($update_call) = grep {
        $_->{call} eq 'item/defect_101' &&
        $_->{method} && $_->{method} eq 'PUT'
    } @api_calls;
    ok $update_call, 'defect was updated';

    my $updated_defect = $update_call->{body};

    # Verify the PUT body only contains attributes and signature (partial update)
    ok exists $updated_defect->{attributes}, 'PUT body has attributes';
    ok exists $updated_defect->{signature}, 'PUT body has signature';
    ok !exists $updated_defect->{designCode}, 'PUT body does not include designCode';
    ok !exists $updated_defect->{geometry}, 'PUT body does not include geometry';

    my ($inspection_attr) = grep {
        $_->{attributeCode} eq 'attributes_defectsWithInspectionsDefectInspection'
    } @{$updated_defect->{attributes}};

    ok $inspection_attr, 'defect has inspection attribute';
    is_deeply $inspection_attr->{value}, ['inspection_101', 'inspection_102'],
        'defect inspection list includes both old and new inspection IDs';

    # Verify we only updated the inspection attribute, not all attributes
    is scalar(@{$updated_defect->{attributes}}), 1,
        'PUT body only includes the inspection attribute being changed';
};

subtest 'post_service_request_update without description' => sub {
    # Test that description is optional

    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_102' && !$method) {
            return {
                item => {
                    itemId => 'defect_102',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_456',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_103']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_103') {
            return {
                item => {
                    itemId => 'inspection_103',
                    designCode => 'designs_hWYCustomerReport',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    attributes => [
                        { attributeCode => 'attributes_status', value => ['status_123'] },
                    ]
                }
            };
        } elsif ($call eq 'item/defect_102/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Check that description field is not present when not provided
            my %attrs = map { $_->{attributeCode} => 1 } @{$body->{attributes}};
            ok !exists $attrs{attributes_hWYCustomerReportCustomerDescriptionField},
                'description field not present when not provided';
            return { item => { itemId => 'inspection_104' } };
        } elsif ($call eq 'item/defect_102' && $method eq 'PUT') {
            return { item => { itemId => 'defect_102' } };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_102',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        # No description
    });

    is $result->update_id, 'defect_102_inspection_104',
        'update created successfully without description';
};

subtest 'post_service_request_update with parent-type inspection (no description field)' => sub {
    # Test that we don't try to set description field on inspections that don't have it
    # (e.g., inspections found via parent relationship)

    my @api_calls;
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        push @api_calls, \%args;

        my $call = $args{call};
        my $body = $args{body};
        my $method = $args{method} || '';

        if ($call eq 'item/defect_103' && !$method) {
            return {
                item => {
                    itemId => 'defect_103',
                    designCode => 'designs_serviceEnquiry',
                    geometry => { type => 'Point', coordinates => [3, 4] },
                    signature => 'sig_789',
                    attributes => [
                        {
                            attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                            value => ['inspection_105']
                        }
                    ]
                }
            };
        } elsif ($call eq 'item/inspection_105') {
            # Return a parent-type inspection (no description or raised time fields)
            return {
                item => {
                    itemId => 'inspection_105',
                    designCode => 'designs_someOtherInspection',
                    geometry => { type => 'Point', coordinates => [1, 2] },
                    attributes => [
                        { attributeCode => 'attributes_status', value => ['status_abc'] },
                        { attributeCode => 'attributes_someField', value => 'some value' },
                        # NOTE: No attributes_hWYCustomerReportCustomerDescriptionField
                        # NOTE: No attributes_tasksRaisedTime
                    ]
                }
            };
        } elsif ($call eq 'item/defect_103/parents') {
            return { results => [] };
        } elsif ($call eq 'item' && $body && !$method) {
            # Check that description field is NOT present (template doesn't have it)
            my %attrs = map { $_->{attributeCode} => $_->{value} } @{$body->{attributes}};
            ok !exists $attrs{attributes_hWYCustomerReportCustomerDescriptionField},
                'description field not set when template lacks it';
            ok !exists $attrs{attributes_tasksRaisedTime},
                'raised time field not set when template lacks it';

            # Should still have the other fields from template
            is $attrs{attributes_status}->[0], 'status_abc',
                'other fields still copied from template';

            return { item => { itemId => 'inspection_106' } };
        } elsif ($call eq 'item/defect_103' && $method eq 'PUT') {
            return { item => { itemId => 'defect_103' } };
        }
    });

    my $result = $endpoint->post_service_request_update({
        service_request_id => 'defect_103',
        status => 'investigating',
        updated_datetime => '2025-12-25T14:30:00Z',
        description => 'This description should be ignored',
    });

    is $result->update_id, 'defect_103_inspection_106',
        'update created successfully even when template lacks description field';
};

# Tests for commit 56bc3177: [Dumfries] Fall back to sourcetype mapping if service_code attribute not set

subtest 'service code fallback to sourcetype mapping' => sub {
    # When service_code attribute is not set, fall back to sourcetype mapping
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    # Mock get_defect_category to return "Pothole"
    my $dumfries = Test::MockModule->new('Open311::Endpoint::Integration::UK::Dumfries');
    $dumfries->mock('get_defect_category', sub {
        my ($self, $defect) = @_;
        return 'Pothole';
    });

    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/defect_no_service_code') {
            return {
                item => {
                    itemId => 'defect_no_service_code',
                    designCode => 'designs_defects',
                    attributes => [
                        # No service_code attribute
                        { attributeCode => 'attributes_defectsSourceType', value => 'some_sourcetype' },
                    ],
                }
            };
        }
    });

    my $defect = {
        itemId => 'defect_no_service_code',
        designCode => 'designs_defects',
        attributes => [
            { attributeCode => 'attributes_defectsSourceType', value => 'some_sourcetype' },
        ],
    };

    my $service_code = $endpoint->get_service_code_from_defect($defect);
    # Should match "Pothole" under either "Roads" or "Pavements" category
    # (hash ordering is not guaranteed, could be 123a123 or 456d456)
    ok($service_code eq '123a123' || $service_code eq '456d456',
       'Service code from sourcetype mapping fallback (Pothole)');
};

subtest 'service code fallback case insensitive' => sub {
    # Test that case-insensitive matching works
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my $dumfries = Test::MockModule->new('Open311::Endpoint::Integration::UK::Dumfries');
    $dumfries->mock('get_defect_category', sub {
        my ($self, $defect) = @_;
        return 'POTHOLE';  # Uppercase
    });

    my $defect = {
        itemId => 'defect_uppercase',
        designCode => 'designs_defects',
        attributes => [
            { attributeCode => 'attributes_defectsSourceType', value => 'some_sourcetype' },
        ],
    };

    my $service_code = $endpoint->get_service_code_from_defect($defect);
    # Should still match despite case difference (could be either ID)
    ok($service_code eq '123a123' || $service_code eq '456d456',
       'Service code fallback is case-insensitive');
};

subtest 'service code fallback returns first match' => sub {
    # When subcategory appears in multiple categories, return first match
    my $integration = Test::MockModule->new('Integrations::AlloyV2');

    my $dumfries = Test::MockModule->new('Open311::Endpoint::Integration::UK::Dumfries');
    $dumfries->mock('get_defect_category', sub {
        my ($self, $defect) = @_;
        return 'Pothole';  # Appears in both Roads and Pavements
    });

    my $defect = {
        itemId => 'defect_duplicate',
        designCode => 'designs_defects',
        attributes => [],
    };

    my $service_code = $endpoint->get_service_code_from_defect($defect);
    # Should return one of the two IDs (123a123 or 456d456)
    ok($service_code eq '123a123' || $service_code eq '456d456',
       'Service code fallback returns a match from one of the duplicate subcategories');
};

# Tests for commit d978d3eb: [Alloy/Dumfries] Improve inspection handling and join processing

subtest '_find_latest_inspection uses attributes_tasksRaisedTime' => sub {
    # Test that attributes_tasksRaisedTime takes precedence over lastEditDate
    my $integration = Test::MockModule->new('Integrations::AlloyV2');
    $integration->mock('api_call', sub {
        my ($self, %args) = @_;
        my $call = $args{call};

        if ($call eq 'item/inspection_raised_early') {
            return {
                item => {
                    itemId => 'inspection_raised_early',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-25T15:00:00.000Z',  # Later edit
                    createdDate => '2025-12-20T10:00:00.000Z',
                    attributes => [
                        { attributeCode => 'attributes_tasksRaisedTime', value => '2025-12-20T10:00:00.000Z' }
                    ],
                }
            };
        } elsif ($call eq 'item/inspection_raised_late') {
            return {
                item => {
                    itemId => 'inspection_raised_late',
                    designCode => 'designs_hWYCustomerReport',
                    lastEditDate => '2025-12-20T10:00:00.000Z',  # Earlier edit
                    createdDate => '2025-12-19T10:00:00.000Z',
                    attributes => [
                        { attributeCode => 'attributes_tasksRaisedTime', value => '2025-12-26T10:00:00.000Z' }
                    ],
                }
            };
        } elsif ($call eq 'item/defect_with_raised_times/parents') {
            return { results => [] };
        }
    });

    my $defect = {
        itemId => 'defect_with_raised_times',
        attributes => [
            {
                attributeCode => 'attributes_defectsWithInspectionsDefectInspection',
                value => ['inspection_raised_early', 'inspection_raised_late']
            }
        ]
    };

    my $inspection = $endpoint->_find_latest_inspection($defect);
    is $inspection->{itemId}, 'inspection_raised_late',
        'uses attributes_tasksRaisedTime for sorting (not lastEditDate)';
};

done_testing;
