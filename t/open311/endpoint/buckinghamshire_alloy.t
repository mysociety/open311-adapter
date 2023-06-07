package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("buckinghamshire_alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Buckinghamshire::Alloy';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("buckinghamshire_alloy.yml")->stringify;
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

    my $content = '[]';
    if ( $is_file ) {
        push @sent, $body;
        return { fileItemId => 'fileid' };
    } elsif ( $body ) {
        push @sent, $body;
        if ( $call eq 'item' ) {
            $content = '{ "item": { "itemId": 12345 } }';
        } elsif ( $call =~ 'aqs/statistics' ) {
            $content = '{ "page":1,"pageSize":20,"results":[{"value":{"attributeCode":"attributes_fake","value":4.0}}] }';
        } elsif ( $call =~ 'aqs/query' ) {
            my $type = $body->{aqs}->{properties}->{dodiCode};
            $content = '{}';
            if ($type eq 'designs_subCategoryList_62d6a1ade83074015715dab2') {
                $content = path(__FILE__)->sibling('json/alloyv2/bucks_categories_search.json')->slurp;
            } elsif ($type eq 'designs_customerReportDefect_62e43ee75039cb015e3287e9') {
                $content = path(__FILE__)->sibling('json/alloyv2/bucks_defects_search.json')->slurp;
            }
        } elsif ( $call =~ 'item-log/item/([^/]*)/reconstruct' ) {
            my $id = $1;
            my $date = $body->{date};
            $date =~ s/\D//g;
            $content = path(__FILE__)->sibling("json/alloyv2/bucks_reconstruct_${id}_$date.json")->slurp;
        }
    } elsif ( $call eq 'design/designs_streetLights' ) {
        $content = path(__FILE__)->sibling('json/alloyv2/occ_design_resource.json')->slurp;
    } elsif ( $call =~ 'item-log/item/(.*)$' ) {
        $content = path(__FILE__)->sibling("json/alloyv2/bucks_item_log_$1.json")->slurp;
    } elsif ( $call eq 'item/abcdef' ) {
        $content = '{ "item": { "designCode": "designs_streetLights" } }';
    } elsif ( $call =~ 'item/(.*)' ) {
        $content = path(__FILE__)->sibling("json/alloyv2/bucks_item_$1.json")->slurp;
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
    set_fixed_time('2023-02-21T13:37:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Drainage_Damaged Gully',
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
        'attribute[category]' => 'Drainage_Damaged Gully',
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
            { attributeCode => 'attributes_customerReportDefectCRMReference_62e43eea0d2c1a0153b1c561', value => 123 },
            { attributeCode => 'attributes_customerReportDefectCategory_62e43eec5039cb015e3287fb', value => ["636b76649446c50391d4205b"] },
            { attributeCode => 'attributes_customerReportDefectCustomerStatus_63690956d76320038c423af5', value => undef },
            { attributeCode => 'attributes_customerReportDefectReportedIssueText_636b830bd1026a0394a10de1', value => "description" },
            { attributeCode => 'attributes_customerReportDefectSubCategory_62e43eed0d2c1a0153b1c56e', value => ["635138684d14750167450719"] },
            { attributeCode => 'attributes_defectsDescription', value => "title" },
            { attributeCode => 'attributes_defectsReportedDate', value => "2023-02-21T13:37:00Z" },
            { attributeCode => 'attributes_defectsReporters', 'value' => [ 12345 ] },
            { attributeCode => 'attributes_itemsGeometry', value => { coordinates => [ 0.1, 50 ], type => "Point" } },
        ],
        designCode => 'designs_customerReportDefect_62e43ee75039cb015e3287e9',
        parents => { "attributes_defectsAssignableDefects" => [ 'abcdef' ] },
    }, 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';
};

subtest "check fetch updates" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2023-02-16T07:43:46Z&end_date=2023-02-16T19:43:46Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
        {
            description => "",
            media_url => "",
            service_request_id => "63ee34826965f30390f01cda",
            status => "open",
            external_status_code => '060',
            update_id => "63ee34826965f30390f01ce3",
            updated_datetime => "2023-02-16T13:49:54Z"
        },
        {
            description => "",
            media_url => "",
            service_request_id => "63ee34826965f30390f01cda",
            status => "action_scheduled",
            external_status_code => '306',
            update_id => "63ee3490b016c303ae032113",
            updated_datetime => "2023-02-16T13:50:08Z"
        }
    ], 'correct json returned';
};


done_testing;
