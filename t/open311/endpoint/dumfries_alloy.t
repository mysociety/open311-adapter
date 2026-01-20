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
    my $is_file = $args{is_file};

    my $content;

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
    is_deeply decode_json($res->content), [ {
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
    }, {
      "status" => "fixed",
      "external_status_code" => "91827eea::",
      "updated_datetime" => "2025-12-25T12:00:00Z",
      "media_url" => "",
      "update_id" => "63ee34826965f30390f01cdc_20251225120000",
      "extras" => {
         "latest_data_only" => 1,
      },
      "description" => "",
      "service_request_id" => "63ee34826965f30390f01cdc"
    } ];
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

done_testing;
