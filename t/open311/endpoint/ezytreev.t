use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::LongString;
use Test::MockTime ':all';
use JSON::MaybeXS;

BEGIN { $ENV{TEST_MODE} = 1; }

set_fixed_time('2020-01-09T12:00:00Z');

my $lwp = Test::MockModule->new('LWP::UserAgent');
$lwp->mock(request => sub {
    my ($ua, $req) = @_;
    if ($req->uri =~ /UpdateEnquiry/) {
        return HTTP::Response->new(200, 'OK', [], '1001');
    } elsif($req->uri =~ /GetEnquiryChanges/) {
        return HTTP::Response->new(200, 'OK', [], encode_json(
            [
                {
                    CRMXRef => 'fms:571             ',
                    EnquiryStatusCode => 'T5',
                    EnqRef => '1001',
                    StatusDate => '2020-01-09T11:30:42Z',
                    EnquiryStatusDescription => 'Works ordered            ',
                    StatusHistory => [
                        {
                            EnquiryStatusCode => 'T1',
                            EnquiryStatusDescription => 'Enquiry received',
                            EnquiryStatusID => 6001,
                            PriorityCode => '',
                            PriorityDescription => '',
                            StatusByID => 'CRM',
                            StatusByName => 'CRM System',
                            StatusDate => '2020-01-09T11:30:42Z',
                            StatusInfo => 'Enquiry received from CRM system',
                        },
                        {
                            EnquiryStatusCode => 'T5',
                            EnquiryStatusDescription => 'Works ordered',
                            EnquiryStatusID => 6014,
                            PriorityCode => '',
                            PriorityDescription => '',
                            StatusByID => 'ENQ',
                            StatusByName => 'Enquiry System Test',
                            StatusDate => '2020-01-10T13:18:00Z',
                            StatusInfo => '',
                        }
                    ]
                }
            ]
        ));
    }
});

my $endpoint_config = {
    endpoint_url => 'http://example.com/',
    username => 'user',
    password => 'pass',
    category_mapping => {
        FallenTree => {
            name => "Fallen/damaged tree or branch",
        },
        TreeDebris => {
            name => "Tree debris",
        },
    },
    reverse_status_mapping => {
        T5 => 'investigating',
    },
    forward_status_mapping => {
        FIXED => 'T8',
    },
};

my $ezytreev_open311_mock = Test::MockModule->new('Open311::Endpoint::Integration::Ezytreev');
$ezytreev_open311_mock->mock(endpoint_config => sub { $endpoint_config });

my $ezytreev_mock = Test::MockModule->new('Integrations::Ezytreev');
$ezytreev_mock->mock(config => sub { $endpoint_config });

use Open311::Endpoint::Integration::Ezytreev;

my $endpoint = Open311::Endpoint::Integration::Ezytreev->new;

subtest "GET services" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services.xml',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_string $res->content, <<XML, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Fallen/damaged tree or branch</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>FallenTree</service_code>
    <service_name>Fallen/damaged tree or branch</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Tree debris</description>
    <group></group>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>TreeDebris</service_code>
    <service_name>Tree debris</service_name>
    <type>realtime</type>
  </service>
</services>
XML
};

subtest "GET service" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/services/FallenTree.xml',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_string $res->content, <<XML, 'xml string ok';
<?xml version="1.0" encoding="utf-8"?>
<service_definition>
  <attributes>
    <attribute>
      <automated>server_set</automated>
      <code>easting</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>easting</description>
      <order>1</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>northing</code>
      <datatype>number</datatype>
      <datatype_description></datatype_description>
      <description>northing</description>
      <order>2</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>fixmystreet_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>external system ID</description>
      <order>3</order>
      <required>true</required>
      <variable>false</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>report_url</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Report URL</description>
      <order>4</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>title</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Title</description>
      <order>5</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>description</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Description</description>
      <order>6</order>
      <required>true</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>asset_details</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Asset information</description>
      <order>7</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>site_code</code>
      <datatype>text</datatype>
      <datatype_description></datatype_description>
      <description>Site code</description>
      <order>8</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>central_asset_id</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Central Asset ID</description>
      <order>9</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>server_set</automated>
      <code>closest_address</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Closest address</description>
      <order>10</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
    <attribute>
      <automated>hidden_field</automated>
      <code>tree_code</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Tree code</description>
      <order>11</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
  </attributes>
  <service_code>FallenTree</service_code>
</service_definition>
XML
};

subtest "POST service request OK" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'FallenTree',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        lat => 51,
        long => -1,
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
        'attribute[description]' => "",
        'attribute[report_url]' => "",
        'attribute[title]' => "",
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => "ezytreev-1001"
        } ], 'correct json returned';
};

subtest 'GET service request updates OK' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.json'
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [
            {
                media_url => '',
                status => "investigating",
                update_id => "ezytreev-update-6014",
                description => "Works ordered",
                service_request_id => "ezytreev-1001",
                updated_datetime => "2020-01-10T13:18:00Z",
                external_status_code => "T5",
            }
        ], 'correct json returned';
};

subtest 'POST service request update OK' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.json',
        status => 'FIXED',
        service_request_id_ext => '571',
        description => '[Customer FMS update] Test update',
        update_id => '42',
        updated_datetime => '2020-01-09T12:00:00Z',
        api_key => 'test',
        service_request_id => 'ezytreev-1001',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [{ update_id => '42' }],
        'correct json returned';
};

done_testing;
