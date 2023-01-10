package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm.yml")->stringify }

package Integrations::Confirm::DummyCustomerRef;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm_customer_ref.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy';
    $args{config_file} = path(__FILE__)->sibling("confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');

package Open311::Endpoint::Integration::UK::DummyOmitLogged;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_omit_logged';
    $args{config_file} = path(__FILE__)->sibling("confirm_omit_logged.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');
sub jurisdiction_id { return 'confirm_dummy_omit_logged'; }

package Open311::Endpoint::Integration::UK::DummyPrivate;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_private';
    $args{config_file} = path(__FILE__)->sibling("confirm_private.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');

package Open311::Endpoint::Integration::UK::DummyPrivateServices;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_private_services';
    $args{config_file} = path(__FILE__)->sibling("confirm_private_services.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Dummy');

package Open311::Endpoint::Integration::UK::DummyCustomerRef;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_dummy_customer_ref';
    $args{config_file} = path(__FILE__)->sibling("confirm_customer_ref.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::DummyCustomerRef');

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::Output;
use Test::Warn;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my ($IC, $SIC, $DC);

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Graffiti', EnquirySubject => [ { SubjectCode => "DEF" } ] },
            ] } }
        };
    } elsif ( $op->name && $op->name eq 'GetEnquiry' ) {
        return { OperationResponse => [
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'FOR', EnquiryDescription => 'this is a for triage report', EnquiryNumber => '2013', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm with no easting/northing', EnquiryNumber => '2004', EnquiryLogTime => '2018-04-17T12:34:57Z', LoggedTime => '2018-04-17T12:34:57Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm with a zero easting/northing', EnquiryNumber => '2005', EnquiryX => '0', EnquiryY => '0', EnquiryLogTime => '2018-04-17T12:34:58Z', LoggedTime => '2018-04-17T12:34:58Z'
          } } }
        ] };
    }
    $op = $op->value;
    if ($op->name eq 'NewEnquiry') {
        # Check more contents of req here
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        is $req{SiteCode}, 999999;
        is $req{EnquiryClassCode}, 'TEST';
        if (defined $req{EnquiryReference} && $req{EnquiryReference} == 1002) {
            ok !defined $req{LoggedTime}, 'LoggedTime omitted';
        }
        if (defined $req{EnquiryReference} && $req{EnquiryReference} == 1003) {
            ok !defined $req{EnquiryAttribute}, 'extra "testing" attribute is ignored';
        }
        if ($req{EnquiryDescription} eq 'Customer Ref report') {
            ok !defined $req{EnquiryReference}, 'EnquiryReference is skipped';
            my %cust = map { $_->name => $_->value } ${$req{EnquiryCustomer}}->value;
            is $cust{CustomerReference}, '1001';
        }
        return { OperationResponse => { NewEnquiryResponse => { Enquiry => { EnquiryNumber => 2001 } } } };
    } elsif ($op->name eq 'EnquiryUpdate') {
        # Check contents of req here
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        if ($req{EnquiryNumber} eq '1002') {
            if ($req{LoggedTime}) {
                return { Fault => { Reason => 'Validate enquiry update.1002.Logged Date 04/06/2018 15:33:28 must be greater than the Effective Date of current status log' } };
            } else {
                return { OperationResponse => { EnquiryUpdateResponse => { Enquiry => { EnquiryNumber => 1002, EnquiryLogNumber => 111 } } } };
            }
        }
        return { OperationResponse => { EnquiryUpdateResponse => { Enquiry => { EnquiryNumber => 2001, EnquiryLogNumber => 2 } } } };
    } elsif ($op->name eq 'GetEnquiryStatusChanges') {
        my %req = map { $_->name => $_->value } ${$op->value}->value;
        if ($req{LoggedTimeFrom} eq '2019-10-23T01:00:00+01:00' && $req{LoggedTimeTo} eq '2019-10-24T01:00:00+01:00') {
          return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
              { EnquiryNumber => 2020, EnquiryStatusLog => [ { EnquiryLogNumber => 5, StatusLogNotes => 'Secret status log notes', LogEffectiveTime => '2019-10-23T12:00:00Z', LoggedTime => '2019-10-23T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
          ] } } };
        } elsif ($req{LoggedTimeFrom} eq '2022-10-23T01:00:00+01:00' && $req{LoggedTimeTo} eq '2022-10-24T01:00:00+01:00') {
          return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
              { EnquiryNumber => 2020, EnquiryStatusLog => [ { EnquiryLogNumber => 5, StatusLogNotes => 'Secret status log notes', LogEffectiveTime => '2019-10-23T12:00:00Z', LoggedTime => '2019-10-23T12:00:00Z', EnquiryStatusCode => 'FIX' } ] },
          ] } } };
        } else {
          return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
              { EnquiryNumber => 2001, EnquiryStatusLog => [ { EnquiryLogNumber => 3, LogEffectiveTime => '2018-03-01T12:00:00Z', LoggedTime => '2018-03-01T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
              { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 1, LogEffectiveTime => '2018-03-01T13:00:00Z', LoggedTime => '2018-03-01T13:00:00Z', EnquiryStatusCode => 'INP' } ] },
              { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 2, LogEffectiveTime => '2018-01-17T12:34:56Z', LoggedTime => '2018-03-01T13:30:00.4000Z', EnquiryStatusCode => 'DUP' } ] },
          ] } } };
        }
    }
    return {};
});

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my $endpoint2 = Open311::Endpoint::Integration::UK::DummyOmitLogged->new;

subtest "GET Service List" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Flooding</description>
    <groups>
      <group>Flooding</group>
      <group>Flooding &amp; Drainage</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Different type of flooding</description>
    <groups>
      <group>Flooding &amp; Drainage</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF_1</service_code>
    <service_name>Different type of flooding</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "GET Service List Description" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/ABC_DEF.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
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
      <datatype>string</datatype>
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
  </attributes>
  <service_code>ABC_DEF</service_code>
</service_definition>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest "POST OK" => sub {
    $IC = 'CS';
    $SIC = 'DP';
    $DC = 'OTS';
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'This is the details',
        'attribute[report_url]' => 'http://example.com/report/1001',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

subtest "POST OK with logged time omitted" => sub {
    $IC = 'CS';
    $SIC = 'DP';
    $DC = 'OTS';
    my $res = $endpoint2->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1002,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'This is the details',
        'attribute[report_url]' => 'http://example.com/report/1001',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

subtest "POST OK with unrecognised attribute" => sub {
    my $res = $endpoint2->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "This is the details",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1003,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'This is the details',
        'attribute[report_url]' => 'http://example.com/report/1003',
        'attribute[testing]' => 'This should be ignored',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};

subtest 'POST with failed document storage' => sub {
    $open311->mock(
        _store_enquiry_documents => sub { die 'Something bad happened' }, );

    my $res;
    warning_is {
        $res = $endpoint->run_test_request(
            POST                        => '/requests.json',
            api_key                     => 'test',
            service_code                => 'ABC_DEF',
            address_string              => '22 Acacia Avenue',
            first_name                  => 'Bob',
            last_name                   => 'Mould',
            'attribute[easting]'        => 100,
            'attribute[northing]'       => 100,
            'attribute[fixmystreet_id]' => 1001,
            'attribute[title]'          => 'Title',
            'attribute[description]'    => 'This is the details',
            'attribute[report_url]'     => 'http://example.com/report/1001',
        )
    }
    'Document storage failed: Something bad happened', 'warning is generated';
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json( $res->content ),
        [ { "service_request_id" => 2001 } ], 'correct json returned';

    $open311->unmock('_store_enquiry_documents');
};

subtest "POST OK with FMS ID in customer ref field" => sub {
    my $endpoint3 = Open311::Endpoint::Integration::UK::DummyCustomerRef->new;
    $IC = 'CS';
    $SIC = 'DP';
    $DC = 'OTS';
    my $res = $endpoint3->run_test_request(
        POST => '/requests.json',
        api_key => 'test',
        service_code => 'ABC_DEF',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        description => "Customer Ref report",
        'attribute[easting]' => 100,
        'attribute[northing]' => 100,
        'attribute[fixmystreet_id]' => 1001,
        'attribute[title]' => 'Title',
        'attribute[description]' => 'Customer Ref report',
        'attribute[report_url]' => 'http://example.com/report/1001',
    );
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 2001
        } ], 'correct json returned';
};


subtest 'POST update' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_request_id => 1001,
        update_id => 123,
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>2001_2</update_id>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest 'POST update with invalid LoggedTime' => sub {
    my $res = $endpoint->run_test_request(
        POST => '/servicerequestupdates.xml',
        api_key => 'test',
        service_request_id => 1002,
        update_id => 123,
        first_name => 'Bob',
        last_name => 'Mould',
        description => 'Update here',
        status => 'OPEN',
        updated_datetime => '2016-09-01T15:00:00Z',
        media_url => 'http://example.org/',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <update_id>1002_111</update_id>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest 'GET update' => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2018-01-01T00:00:00Z&end_date=2018-02-01T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_request_updates>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <media_url></media_url>
    <service_request_id>2001</service_request_id>
    <status>in_progress</status>
    <update_id>2001_3</update_id>
    <updated_datetime>2018-03-01T12:00:00+00:00</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>INP</external_status_code>
    <media_url></media_url>
    <service_request_id>2002</service_request_id>
    <status>in_progress</status>
    <update_id>2002_1</update_id>
    <updated_datetime>2018-03-01T13:00:00+00:00</updated_datetime>
  </request_update>
  <request_update>
    <description></description>
    <external_status_code>DUP</external_status_code>
    <media_url></media_url>
    <service_request_id>2002</service_request_id>
    <status>duplicate</status>
    <update_id>2002_2</update_id>
    <updated_datetime>2018-03-01T13:30:00+00:00</updated_datetime>
  </request_update>
</service_request_updates>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest 'GET reports' => sub {
    local $ENV{TEST_LOGGER} = 'warn';
    my $res;
    stderr_like {
        $res = $endpoint->run_test_request(
            GET => '/requests.xml?jurisdiction_id=confirm_dummy&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z',
        );
    } qr{no easting/northing for Enquiry 2004\n.*?no easting/northing for Enquiry 2005\n}, 'Warnings about invalid locations output';
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <address></address>
    <address_id></address_id>
    <description>this is a report from confirm</description>
    <lat>100</lat>
    <long>100</long>
    <media_url></media_url>
    <requested_datetime>2018-04-17T13:34:56+01:00</requested_datetime>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <service_request_id>2003</service_request_id>
    <status>in_progress</status>
    <updated_datetime>2018-04-17T13:34:56+01:00</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest "fetching of completion photos" => sub {
    my $lwp = Test::MockModule->new('LWP::UserAgent');
    $lwp->mock(request => sub {
        my ($ua, $req) = @_;
        return HTTP::Response->new(200, 'OK', [], '{"access_token":"123","expires_in":3600}') if $req->uri =~ /oauth\/token/;
        return HTTP::Response->new(200, 'OK', [], '{"primaryJobNumber":"432"}') if $req->uri =~ /enquiries\/2020/;
        return HTTP::Response->new(200, 'OK', [], '{"documents":[
            {"documentNo":1,"fileName":"photo1.jpeg","documentNotes":"Before"},
            {"documentNo":2,"fileName":"photo2.jpeg","documentNotes":"After"}
            ]}') if $req->uri =~ /jobs\/432/;
    });
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2022-10-23T00:00:00Z&end_date=2022-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<media_url>http://example.com/photo/completion?jurisdiction_id=confirm_dummy&amp;job=432&amp;photo=1</media_url>';
};

$endpoint = Open311::Endpoint::Integration::UK::DummyPrivate->new;

subtest 'GET reports - private' => sub {
    local $ENV{TEST_LOGGER} = 'warn';
    my $res;
    stderr_like {
        $res = $endpoint->run_test_request(
          GET => '/requests.xml?jurisdiction_id=confirm_dummy_private&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z',
        );
    } qr{no easting/northing for Enquiry 2004\n.*?no easting/northing for Enquiry 2005\n}, 'Warnings about invalid locations output';
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <address></address>
    <address_id></address_id>
    <description>this is a report from confirm</description>
    <lat>100</lat>
    <long>100</long>
    <media_url></media_url>
    <non_public>1</non_public>
    <requested_datetime>2018-04-17T13:34:56+01:00</requested_datetime>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <service_request_id>2003</service_request_id>
    <status>in_progress</status>
    <updated_datetime>2018-04-17T13:34:56+01:00</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

$endpoint = Open311::Endpoint::Integration::UK::DummyPrivateServices->new;

subtest "GET Service List - private services" => sub {
    my $res = $endpoint->run_test_request( GET => '/services.xml?jurisdiction_id=confirm_dummy_private_services' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Flooding</description>
    <groups>
      <group>Flooding &amp; Drainage</group>
    </groups>
    <keywords>private</keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest 'GET reports - private services' => sub {
    local $ENV{TEST_LOGGER} = 'warn';
    my $res;
    stderr_like {
        $res = $endpoint->run_test_request(
          GET => '/requests.xml?jurisdiction_id=confirm_dummy_private_services&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z',
        );
    } qr{no easting/northing for Enquiry 2004\n.*?no easting/northing for Enquiry 2005\n}, 'Warnings about invalid locations output';
    ok $res->is_success, 'valid request' or diag $res->content;

my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<service_requests>
  <request>
    <address></address>
    <address_id></address_id>
    <description>this is a report from confirm</description>
    <lat>100</lat>
    <long>100</long>
    <media_url></media_url>
    <non_public>1</non_public>
    <requested_datetime>2018-04-17T13:34:56+01:00</requested_datetime>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <service_request_id>2003</service_request_id>
    <status>in_progress</status>
    <updated_datetime>2018-04-17T13:34:56+01:00</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

subtest "StatusLogNotes shouldn't appear in updates" => sub {
    my $res = $endpoint->run_test_request(
        GET => '/servicerequestupdates.xml?start_date=2019-10-23T00:00:00Z&end_date=2019-10-24T00:00:00Z',
    );
    ok $res->is_success, 'valid request' or diag $res->content;
    contains_string $res->content, '<update_id>2020_5</update_id>';
    lacks_string $res->content, 'Secret status log notes';
};

done_testing;
