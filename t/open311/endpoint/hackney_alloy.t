package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("hackney_alloy_environment.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Hackney::Environment';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("hackney_alloy_environment.yml")->stringify;
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
    if ( $body ) {
        push @sent, $body;
        if ( $call eq 'item' ) {
            $content = '{ "item": { "itemId": 12345 } }';
        } elsif ( $call =~ 'aqs/statistics' ) {
            $content = '{ "page":1,"pageSize":20,"results":[{"value":{"attributeCode":"attributes_fake","value":4.0}}] }';
        } elsif ( $call =~ 'aqs/query' ) {
            my $type = $body->{aqs}->{properties}->{dodiCode};
            $content = '{}';
            if ($type eq 'designs_fMSCategory') {
                $content = path(__FILE__)->sibling('json/hackney_environment/categories_search.json')->slurp;
            } elsif ($type eq 'designs_contacts') {
                $content = path(__FILE__)->sibling('json/hackney_environment/contacts_search.json')->slurp;
            } elsif ($type eq 'designs_fixedMyStreetDefect') {
                $content = path(__FILE__)->sibling('json/hackney_environment/defects_search.json')->slurp;
            }
        } elsif ( $call =~ 'item-log/item/([^/]*)/reconstruct' ) {
            my $id = $1;
            my $date = $body->{date};
            $date =~ s/\D//g;
            warn path(__FILE__)->sibling("json/hackney_environment/reconstruct_${id}_$date.json");
            $content = path(__FILE__)->sibling("json/hackney_environment/reconstruct_${id}_$date.json")->slurp;
        }
    } elsif ( $call =~ 'item-log/item/(.*)$' ) {
        $content = path(__FILE__)->sibling("json/hackney_environment/item_log_$1.json")->slurp;
    } elsif ( $call =~ 'item/(\w+)/parents' ) {
        my $fh = path(__FILE__)->sibling("json/hackney_environment/item_$1_parents.json");
        if ( $fh->exists ) {
            warn $fh;
            $content = $fh->slurp;
        } else {
            $content = '{ "results": [] }';
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
        jurisdiction_id => 'hackney',
        api_key => 'key',
        service_code => 'Graffiti',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => 'title',
        'attribute[report_url]' => 'http://localhost/123',
        'attribute[asset_resource_id]' => undef,
        'attribute[category]' => 'Graffiti',
        'attribute[fixmystreet_id]' => 123,
        'attribute[closest_address]' => "27 Hillman Street, Hackney E8 1AB",
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[requested_datetime]' => '2022-04-19T09:39:53+01:00',
        'attribute[graffiti_landtype]' => 'public land',
        'attribute[graffiti_offensive]' => 'yes',
        'attribute[graffiti_size]' => 5,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    # order these so comparison works
    $sent->{attributes} = [ sort { $a->{attributeCode} cmp $b->{attributeCode} } @{ $sent->{attributes} } ];
    is_deeply $sent, {
        attributes => [
            { attributeCode => 'attributes_defectsDescription', value => "description" },
            { attributeCode => 'attributes_defectsReportedDate', value => "2022-04-19T09:39:53+01:00" },
            { attributeCode => 'attributes_fixedMyStreetDefectContactDetails', value => [ "abcdea5823d4d9016616c151" ] },
            { attributeCode => 'attributes_fixedMyStreetDefectFMSCategory', value => [ "abcde0d6dcf79201591d720f" ] },
            { attributeCode => 'attributes_fixedMyStreetDefectFMSID', value => 123 },
            { attributeCode => 'attributes_fixedMyStreetDefectFMSNearestAddress', value => "27 Hillman Street, Hackney E8 1AB" },
            { attributeCode => 'attributes_fixedMyStreetDefectFMSReportTitle', value => "title" },
            { attributeCode => 'attributes_fixedMyStreetDefectGraffitiOffensive', value => "yes" },
            { attributeCode => 'attributes_fixedMyStreetDefectGraffitiSize', value => 5 },
            { attributeCode => 'attributes_fixedMyStreetDefectGraffitiType', value => "public land" },
            { attributeCode => 'attributes_itemsGeometry', value => { coordinates => [ 0.1, 50 ], type => "Point" } },
        ],
        designCode => 'designs_fixedMyStreetDefect',
        parents => { },
    }, 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';
};

subtest "check fetch updates" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2022-04-20T07:43:46Z&end_date=2022-04-20T19:43:46Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
        {
            description => "",
            media_url => "",
            service_request_id => "625ffffffffae7015ac40c5b",
            status => "open",
            update_id => "625fffffff62a1016ce7f779",
            updated_datetime => "2022-04-20T08:19:26Z"
        },
        {
            description => "",
            media_url => "",
            service_request_id => "625ffffffffae7015ac40c5b",
            # this is derived from the Hackney Environment-specific defect_status code
            status => "not_councils_responsibility",
            update_id => "625fe4b24edcdb01584733b2",
            updated_datetime => "2022-04-20T10:47:14Z"
        }
    ], 'correct json returned';
};

done_testing;
