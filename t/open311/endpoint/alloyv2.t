package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';
use utf8;

has content => (
    is => 'ro',
    isa => Str,
    default => '[]',
    coerce => sub { encode_utf8($_[0]) }
);

has code => (
    is => 'ro',
    isa => Str,
    default => '200',
);

has message => (
    is => 'ro',
    isa => Str,
    default => 'OK',
);

has is_success => (
    is => 'ro',
    isa => Bool,
    default => 1
);

package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("alloyv2.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("alloyv2.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');
sub service_request_content { '/open311/service_request_extended' }

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';
use Encode;

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my %responses = (
    resource => '{
    }',
);

my @sent;
my @calls;

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};

    my $content = '[]';
    push @calls, $call;
    if ( $body ) {
        push @sent, $body;
        if ( $call eq 'item' ) {
            $content = '{ "item": { "itemId": 12345 } }';
        } elsif ( $call eq 'item/12345' ) {
            $content = '{ "start": "2019-01-01T12:00:00Z" }';
        } elsif ( $call =~ 'aqs/statistics' ) {
            $content = '{ "result": 4.0 }';
        } elsif ( $call =~ 'aqs/query' ) {
            my $type = $body->{properties}->{dodiCode};
            my $time = $body->{children}->[0]->{children}->[1]->{properties}->{value}->[0];
            $content = '{}';
            if ( $type =~ /DEFECT/i ) {
                if ( $time =~ /2019-01-02/ ) {
                    $content = path(__FILE__)->sibling('json/alloyv2/defect_search_all.json')->slurp;
                }
            } else {
                $content = path(__FILE__)->sibling('json/alloyv2/inspect_search.json')->slurp;
            }
        } elsif ( $call =~ 'item-log/item/([^/]*)/reconstruct' ) {
            my $id = $1;
            my $date = $body->{date};
            $date =~ s/\D//g;
            $content = path(__FILE__)->sibling("json/alloyv2/reconstruct_${id}_$date.json")->slurp;
        }
    } else {
        if ( $call eq 'design/designs_enquiryInspectionRFS1001181_5d3245c5fe2ad806f8dfbaf6' ) {
            $content = path(__FILE__)->sibling('json/alloyv2/design_rfs.json')->slurp;
        } elsif ( $call eq 'design/a_design_code' ) {
            $content = path(__FILE__)->sibling('json/alloyv2/design_resource.json')->slurp;
        } elsif ( $call eq 'item/39dhd38dhdkdnxj' ) {
            $content = '{ "item": { "designCode": "a_design_code" } }';
        } elsif ( $call =~ 'item-log/item/(.*)$' ) {
            $content = path(__FILE__)->sibling("json/alloyv2/item_log_$1.json")->slurp;
        } else {
            $content = $responses{$call};
        }
    }

    $content ||= '[]';

    my $result = decode_json(encode_utf8($content));
    return $result;
});

subtest "create basic problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => '39dhd38dhdkdnxj',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    # order these so comparison works
    $sent->{attributes} = [ sort { $a->{attributeCode} cmp $b->{attributeCode} } @{ $sent->{attributes} } ];
    is_deeply $sent,
    {
    attributes => [
        #{ attributeCode => 'attributes_enquiryInspectionRFS1001181Category1011685_5d3245dbfe2ad806f8dfbb33', value => 'Category' },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181Explanation1009860_5d3245d5fe2ad806f8dfbb1a', value => "description" },
        #{ attributeCode  => 'attributes_enquiryInspectionRFS1001181FMSContact1010927_5d3245d9fe2ad806f8dfbb29', value => [ 708823 ] },
        { attributeCode  => 'attributes_enquiryInspectionRFS1001181ReportedDateTime1009861_5d3245d7fe2ad806f8dfbb1f', value => '2014-01-01T12:00:00Z' },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181SourceID1009855_5d3245d1fe2ad806f8dfbb06', value => 1 },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181Summary1009859_5d3245d4fe2ad806f8dfbb15', value => 1 },
    ],
    designCode => 'designs_enquiryInspectionRFS1001181_5d3245c5fe2ad806f8dfbaf6',
    geometry => {
        coordinates => [
            0.1,
            50
        ],
        type => "Point"
    },
    parents => { "attribute_design_code" => [ '39dhd38dhdkdnxj' ] },
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "create problem with no resource_id" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request( 
        POST => '/requests.json', 
        jurisdiction_id => 'dummy',
        api_key => 'test',
        service_code => 'Kerbs_Missing',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[title]' => '1',
        'attribute[report_url]' => 'http://localhost/1',
        'attribute[asset_resource_id]' => '',
        'attribute[easting]' => 1,
        'attribute[northing]' => 2,
        'attribute[category]' => 'Kerbs_Missing',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    $sent->{attributes} = [ sort { $a->{attributeCode} cmp $b->{attributeCode} } @{ $sent->{attributes} } ];
    is_deeply $sent,
    {
    attributes => [
        #{ attributeCode => 'attributes_enquiryInspectionRFS1001181Category1011685_5d3245dbfe2ad806f8dfbb33', value => 'Category' },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181Explanation1009860_5d3245d5fe2ad806f8dfbb1a', value => "description" },
        #{ attributeCode  => 'attributes_enquiryInspectionRFS1001181FMSContact1010927_5d3245d9fe2ad806f8dfbb29', value => [ 708823 ] },
        { attributeCode  => 'attributes_enquiryInspectionRFS1001181ReportedDateTime1009861_5d3245d7fe2ad806f8dfbb1f', value => '2014-01-01T12:00:00Z' },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181SourceID1009855_5d3245d1fe2ad806f8dfbb06', value => 1 },
        { attributeCode => 'attributes_enquiryInspectionRFS1001181Summary1009859_5d3245d4fe2ad806f8dfbb15', value => 1 },
    ],
    designCode => 'designs_enquiryInspectionRFS1001181_5d3245c5fe2ad806f8dfbaf6',
    geometry => {
        coordinates => [
            0.1,
            50
        ],
        type => "Point"
    },
    parents => {},
    }
    , 'correct json sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 12345
        } ], 'correct json returned';

};

subtest "check fetch updates" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/servicerequestupdates.json?jurisdiction_id=dummy&start_date=2019-01-01T00:00:00Z&end_date=2019-03-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        status => 'investigating',
        service_request_id => '3027029',
        description => '',
        updated_datetime => '2019-01-01T00:22:40Z',
        update_id => '5d32469bb4e1b90150014306',
        media_url => '',
    },
    {
        status => 'investigating',
        service_request_id => '3027029',
        description => 'This is an updated customer response',
        updated_datetime => '2019-01-01T00:32:40Z',
        update_id => '5d32469bb4e1b90150014305',
        media_url => '',
    },
    {
        status => 'investigating',
        service_request_id => '3027030',
        description => '',
        updated_datetime => '2019-01-01T01:42:40Z',
        update_id => '5d32469bb4e1b90150014307',
        media_url => '',
    },
    {
        status => 'not_councils_responsibility',
        service_request_id => '3027031',
        description => '',
        updated_datetime => '2019-01-01T01:43:40Z',
        update_id => '6d32469bb4e1b90150014305',
        media_url => '',
        external_status_code => '01b51bb5c0de101a004154b5',
    },
    #{
        #status => 'fixed',
        #service_request_id => '4947502',
        #description => '',
        #updated_datetime => '2019-02-19T09:11:08Z',
        #update_id => '271877',
        #media_url => '',
        #fixmystreet_id => '10034',
    #}
    ], 'correct json returned';
};

subtest "check fetch problem" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
      GET => '/requests.json?jurisdiction_id=dummy&start_date=2019-01-02T00:00:00Z&end_date=2019-01-01T02:00:00Z',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [{
      long => 2,
      requested_datetime => "2019-01-02T11:29:16Z",
      service_code => "Shelter Damaged",
      updated_datetime => "2019-01-02T11:29:16Z",
      service_name => "Shelter Damaged",
      address_id => "",
      lat => 1,
      description => "test",
      service_request_id => 4947505,
      zipcode => "",
      media_url => "",
      status => "investigating",
      address => ""
   },
   {
      address_id => "",
      lat => 1,
      service_request_id => 4947597,
      description => "fill",
      service_name => "Grit Bin - empty/refill",
      status => "fixed",
      media_url => "",
      address => "",
      zipcode => "",
      requested_datetime => "2019-01-02T14:44:53Z",
      long => 2,
      updated_datetime => "2019-01-02T14:44:53Z",
      service_code => "Grit Bin - damaged/replacement",
      service_code => "Grit Bin - empty/refill"
   }], "correct json returned";
};

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=dummy',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [ {
        service_code => 'Bus Stops_Shelter Damaged',
        service_name => "Shelter Damaged",
        description => "Shelter Damaged",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Bus Stops"
    },
    {
        service_code => 'Bus Stops_Sign/Pole Damaged',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Bus Stops",
        service_name => "Sign/Pole Damaged",
        description => "Sign/Pole Damaged"
    },
    {
        service_code => 'Drain Covers_Broken / Missing',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Drain Covers",
        service_name => "Broken / Missing",
        description => "Broken / Missing"
    },
    {
        service_code => 'Drain Covers_Loose / Raised/Sunken',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Drain Covers",
        service_name => "Loose / Raised/Sunken",
        description => "Loose / Raised/Sunken"
    },
    {
        service_code => 'Highway Bridges_Highway Bridges - Damaged/Unsafe',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Highway Bridges",
        service_name => "Highway Bridges - Damaged/Unsafe",
        description => "Highway Bridges - Damaged/Unsafe"
    },
    {
        service_code => 'Kerbs_Damaged/Loose',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Kerbs",
        service_name => "Damaged/Loose",
        description => "Damaged/Loose"
    },
    {
        service_code => 'Kerbs_Missing',
        metadata => 'true',
        type => "realtime",
        keywords => "",
        group => "Kerbs",
        service_name => "Missing",
        description => "Missing"
    } ], 'correct json returned';
};

subtest "check fetch service metadata" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/Highway%20Bridges_Highway%20Bridges%20-%20Damaged/Unsafe.json?jurisdiction_id=dummy',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "Highway Bridges_Highway Bridges - Damaged/Unsafe",
        attributes => [
          {
            variable => 'false',
            code => "easting",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 1,
            description => "easting",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "northing",
            datatype => "number",
            required => 'true',
            datatype_description => '',
            order => 2,
            description => "northing",
            automated => 'server_set',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "report_url",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 4,
            description => "Report URL",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "title",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 5,
            description => "Title",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "description",
            datatype => "text",
            required => 'true',
            datatype_description => '',
            order => 6,
            description => "Description",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "category",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 7,
            description => "Category",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "asset_resource_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 8,
            description => "Asset resource ID",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "emergency",
            datatype => "text",
            required => 'false',
            datatype_description => '',
            order => 9,
            description => "This is an emergency",
          },
        ]
    }, 'correct json returned';
};

restore_time();
done_testing;
