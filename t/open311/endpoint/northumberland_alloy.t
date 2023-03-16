package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("northumberland_alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::NorthumberlandAlloy';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("northumberland_alloy.yml")->stringify;
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

    push @sent, $body if $body;

    my $content = undef;

    if ($call =~ 'item/defect_1/parents' || $call =~ 'item/defect_2/parents') {

        # Looking up defect parents - returning no parents.
        $content = path(__FILE__)->sibling("json/alloyv2/northumberland_empty_response.json")->slurp;

    } elsif ($call =~ 'design/designs_nCCLightingUnit_62cd4755a76c5d014f282213') {

        # Looking up asset's design.
        $content = path(__FILE__)->sibling("json/alloyv2/northumberland_asset_design_lookup_response.json")->slurp;

    } elsif ($call =~ 'item/asset') {

        # Looking up asset.
        $content = path(__FILE__)->sibling("json/alloyv2/northumberland_asset_lookup_response.json")->slurp;

    } elsif ($body && $call =~ 'item') {
        my $designCode = $body->{designCode};

        if ($designCode eq 'designs_contacts') {

            # Creating a new contact.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_create_contact_response.json")->slurp;

        } elsif ($designCode eq 'designs_customerRequest_6386279ffb3d97038c4e03a9') {

            # Creating a new report.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_create_report_response.json")->slurp;
        }

    } elsif ($body && $call =~ 'aqs/statistics') {
        my $designCode = $body->{aqs}->{properties}->{dodiCode};

        if ($designCode eq 'designs_contacts') {

            # Searching for a non-existent contact.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_contact_not_found_response.json")->slurp;

        } elsif ($designCode eq 'designs_cRMRequests_5d89e289ca31500a94693c9c') {

            # Counting how many categories there are.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_categories_count_response.json")->slurp;

        } elsif ($designCode eq 'designs_cRMRequestTypes_5d89dffaca31500a94693bde') {

            # Counting how many groups there are.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_groups_count_response.json")->slurp;

        } elsif ($designCode eq 'designInterfaces_highwaysDefaults_633d608998cee30390f63cd1') {

            # Counting how many defects there are.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_defects_count_response.json")->slurp;
        }

    } elsif ($body && $call =~ 'aqs/query') {
        my $designCode = $body->{aqs}->{properties}->{dodiCode};

        if ($designCode eq 'designs_cRMRequests_5d89e289ca31500a94693c9c') {

            # Querying all categories.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_categories_query_response.json")->slurp;

        } elsif ($designCode eq 'designs_cRMRequestTypes_5d89dffaca31500a94693bde') {

            # Querying all groups.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_groups_query_response.json")->slurp;

        } elsif ($designCode eq 'designInterfaces_highwaysDefaults_633d608998cee30390f63cd1') {

            # Querying defects.
            $content = path(__FILE__)->sibling("json/alloyv2/northumberland_defects_query_response.json")->slurp;

        }
    }

    if (!$content) {
        warn "No handler found for API call " . $call . "  " . encode_json($body);
        return decode_json('[]');
    }

    return decode_json(encode_utf8($content));
});

subtest "create basic problem" => sub {
    set_fixed_time('2023-02-21T13:37:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Street Lighting_Damaged / Missing / Facing Wrong Way',
        first_name => 'David',
        last_name => 'Anthony',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => 'title',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[asset_resource_id]' => 'asset',
        'attribute[category]' => 'Street Lighting_Damaged / Missing / Facing Wrong Way',
        'attribute[fixmystreet_id]' => 123,
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
    );
    restore_time();

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    # order these so comparison works
    $sent->{attributes} = [ sort { $a->{attributeCode} cmp $b->{attributeCode} } @{ $sent->{attributes} } ];
    is_deeply $sent, {
        attributes => [
            { attributeCode => 'attributes_customerRequestFMSDescription_63862bed05cb250393c2096d', value => 'description' },
            { attributeCode => 'attributes_customerRequestFMSSummary_63862bd505cb250393c204d7', value => "title" },
            { attributeCode => 'attributes_customerRequestFixMyStreetID_63862c38bafbd20397883f72', value => 123 },
            { attributeCode => 'attributes_customerRequestMainFMSStatus_63fcb297c9ec9c036ec35dfb', value => undef },
            { attributeCode => 'attributes_customerRequestReporter_63f4c227dabda80390d2f0ab', value => [ '6420576dac3acd036a974043' ]},
            { attributeCode => 'attributes_customerRequestRequestCategory_63862851fb3d97038c4e1cfc', value => [ '61fb016c4c5c56015448093f' ]},
            { attributeCode => 'attributes_customerRequestRequestGroup_638627f005cb250393c1705a', value => [ '61fafee3e3b879015205f7cb' ]},
            { attributeCode => 'attributes_itemsGeometry', value => { coordinates => [ 0.1, 50 ], type => "Point" } },
            { attributeCode => 'attributes_tasksRaisedTime', value => '2023-02-21T13:37:00Z' },
        ],
        designCode => 'designs_customerRequest_6386279ffb3d97038c4e03a9',
        parents => { "attributes_tasksAssignableTasks" => [ 'asset' ] },
    }, 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "642062376be3a0036bbbb64b"
        } ], 'correct json returned';
};

subtest "fetch problems" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/requests.json?jurisdiction_id=dummy&start_date=2023-03-23T00:00:00Z&end_date=2023-03-24T00:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is_deeply decode_json($res->content),
    [
        {
            address => "",
            address_id => "",
            lat => 55.0973679211959,
            long => -1.59105589317734,
            media_url => "",
            requested_datetime => "2023-03-23T00:00:00Z",
            service_code => "Roads_Highway Condition",
            service_name => "Roads_Highway Condition",
            service_request_id => "defect_1",
            status => "open",
            updated_datetime => "2023-03-23T00:00:00Z",
            zipcode => "",
        },
    ], 'correct json returned';
};


done_testing;
