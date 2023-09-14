package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("oxfordshire_alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Oxfordshire::AlloyV2';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("oxfordshire_alloy.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use Open311::Endpoint;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my (@sent);

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};
    my $is_file = $args{is_file};

    my $content = '[]';
    if ( $is_file ) {
        push @sent, $body;
        return { fileItemId => 'fileid' };
    } elsif ( $body ) {
        push @sent, $body;
        if ( $call eq 'item/123456???' ) {
            $content = '{ "item": { "signature": "5d32469bb4e1b90150014310" } }';
        } elsif ( $call eq 'item' ) {
            $content = '{ "item": { "itemId": 12345 } }';
        } elsif ( $call =~ 'aqs/statistics' ) {
            $content = '{ "page":1,"pageSize":20,"results":[{"value":{"attributeCode":"attributes_fake","value":4.0}}] }';
        } elsif ( $call =~ 'aqs/query' ) {
            my $type = $body->{aqs}->{properties}->{dodiCode};
            $content = '{}';
            if ($type eq 'designs_faultType_123456') {
                $content = path(__FILE__)->sibling('json/alloyv2/occ_categories_search.json')->slurp;
            } elsif ($type eq 'designs_lightingJob') {
                $content = path(__FILE__)->sibling('json/alloyv2/occ_lightingjob_search.json')->slurp;
            } elsif ($type eq 'designs_damageReport') {
                $content = path(__FILE__)->sibling('json/alloyv2/occ_damagereport_search.json')->slurp;
            }
        }
    } else {
        if ( $call eq "design/designs_lightingDefect_123456" ) {
            $content = path(__FILE__)->sibling('json/alloyv2/occ_design.json')->slurp;
        } elsif ( $call eq 'design/designs_streetLights' ) {
            $content = path(__FILE__)->sibling('json/alloyv2/occ_design_resource.json')->slurp;
        } elsif ( $call eq 'item/abcdef' ) {
            $content = '{ "item": { "designCode": "designs_streetLights" } }';
        } elsif ( $call =~ 'item/(\w+)/parents' ) {
            my $fh = path(__FILE__)->sibling("json/alloyv2/occ_item_$1_parents.json");
            if ( $fh->exists ) {
                $content = $fh->slurp;
            } else {
                $content = '{ "results": [] }';
            }
        }
    }

    $content ||= '[]';

    my $result;
    eval {
        $result = decode_json(encode_utf8($content));
    };
    if ($@) {
        warn $content;
        return decode_json('[]');
    }
    return $result;
});

subtest "create basic problem" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Lamp_on_during_day',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => 'title',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[asset_resource_id]' => 'abcdef',
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 123,
        'attribute[usrn]' => 'USRN',
        'attribute[closest_address]' => "Nearest road: Closest\n\nNearest postcode: ZZ1 1ZZ\n\n",
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[mayrise_id]' => 'MID',
        'attribute[unit_number]' => '10',
        'attribute[staff_role]' => 'Patrol',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    # order these so comparison works
    $sent->{attributes} = [ sort { $a->{attributeCode} cmp $b->{attributeCode} } @{ $sent->{attributes} } ];
    is_deeply $sent, {
        attributes => [
            { attributeCode => 'attributes_defectsDescription', value => "title" },
            { attributeCode => 'attributes_itemsGeometry', value => { coordinates => [ 0.1, 50 ], type => "Point" } },
            { attributeCode => 'attributes_lightingDefectCRMReference_123456', value => 123 },
            { attributeCode => 'attributes_lightingDefectCustomerComments_123456', value => "description" },
            { attributeCode => 'attributes_lightingDefectFMSReport_123456', value => "http://localhost/123" },
            { attributeCode => 'attributes_lightingDefectFaultType_123456', value => ["5edf3f9b5f93330056cb375c"] },
            { attributeCode => 'attributes_lightingDefectNearestCalculatedAddress_123456', value => "Closest" },
            { attributeCode => 'attributes_lightingDefectSource_60953d', value => ['5ef1c835457bbc00569a9a3c'] },
            { attributeCode => 'attributes_lightingDefectUSRN_123456', value => "USRN" },
            { attributeCode => 'attributes_mayriseIdentifierMayriseIdentifier', value => "MID" },
            { attributeCode => 'attributes_streetLightingUnitsUnitNumber', value => "10" },
            { attributeCode => 'attributes_tasksRaisedTime', value => $sent->{attributes}[11]{value} },
        ],
        designCode => 'designs_lightingDefect_123456',
        parents => { "attributes_defectsAssignableDefects" => [ 'abcdef' ] },
    }, 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';
};

subtest 'fetch problems' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/requests.json',
        jurisdiction_id => 'dummy',
        api_key => 'test',
        start_date => "2021-08-01T12:00:00Z",
        end_date => "2021-08-02T12:00:00Z",
    );

    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            service_request_id => "61278c1e80483601696619b1",
            service_code => "HIT",
            service_name => "HIT",
            requested_datetime => "2021-08-26T12:42:07Z",
            updated_datetime => "2021-08-26T12:42:07Z",
            status => "action_scheduled",
            lat => 51.53706,
            long => -0.909062,
            address => "",
            address_id => "",
            zipcode => "",
            media_url => "",
        }, {
            service_request_id => "615c8aaca3e810015b7106e6",
            service_code => "Vehicle_damage",
            service_name => "Vehicle damage",
            requested_datetime => "2021-10-05T17:26:00Z",
            updated_datetime => "2021-10-05T17:26:00Z",
            status => "action_scheduled",
            lat => 52.05927,
            long => -1.348509,
            address => "",
            address_id => "",
            zipcode => "",
            media_url => "",
        }
    ], 'correct json returned';
};

done_testing;
