package Integrations::Confirm::Bexley::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm::Bexley';
with 'Role::Config';
has config_filename => ( is => 'ro', default => 'dummy' );
sub _build_config_file { path(__FILE__)->sibling("bexley_confirm.yml")->stringify }

package Open311::Endpoint::Integration::UK::Bexley::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Bexley::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{config_file} = path(__FILE__)->sibling("bexley_confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Bexley::Dummy');

package main;

use strict;
use warnings;

use Path::Tiny;
use Test::More;
use Test::MockModule;
use Test::Output;
use Test::LongString;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm::Bexley');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Flooding', EnquirySubject => [ { SubjectCode => "DEF" } ] },
                { ServiceCode => 'GHI', ServiceName => 'Graffiti', EnquirySubject => [ { SubjectCode => "JKL" } ] },
            ] } }
        };
    } elsif ( $op->name && $op->name eq 'GetEnquiry' ) {
        return { OperationResponse => [
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm', EnquiryNumber => '2003', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm with no easting/northing', EnquiryNumber => '2004', EnquiryLogTime => '2018-04-17T12:34:57Z', LoggedTime => '2018-04-17T12:34:57Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'ABC', SubjectCode => 'DEF', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is a report from confirm with a zero easting/northing', EnquiryNumber => '2005', EnquiryX => '0', EnquiryY => '0', EnquiryLogTime => '2018-04-17T12:34:58Z', LoggedTime => '2018-04-17T12:34:58Z'
          } } },
          { GetEnquiryResponse => { Enquiry => {
            ServiceCode => 'GHI', SubjectCode => 'JKL', EnquiryStatusCode => 'INP', EnquiryDescription => 'this is another report from confirm', EnquiryNumber => '2006', EnquiryX => '100', EnquiryY => '100', EnquiryLogTime => '2018-04-17T12:34:56Z', LoggedTime => '2018-04-17T12:34:56Z'
          } } },
        ] };
    }
    $op = $op->value;
    if ($op->name eq 'GetEnquiryStatusChanges') {
        return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
            { EnquiryNumber => 2001, EnquiryStatusLog => [ { EnquiryLogNumber => 3, LogEffectiveTime => '2018-03-01T12:00:00Z', LoggedTime => '2018-03-01T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 1, LogEffectiveTime => '2018-03-01T13:00:00Z', LoggedTime => '2018-03-01T13:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 2, LogEffectiveTime => '2018-01-17T12:34:56Z', LoggedTime => '2018-03-01T13:30:00.4000Z', EnquiryStatusCode => 'DUP' } ] },
        ] } } };
    }
    return {};
});

my $endpoint = Open311::Endpoint::Integration::UK::Bexley::Confirm::Dummy->new;

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
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF</service_code>
    <service_name>Flooding</service_name>
    <type>realtime</type>
  </service>
  <service>
    <description>Graffiti</description>
    <groups>
      <group>Graffiti</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>GHI_JKL</service_code>
    <service_name>Graffiti</service_name>
    <type>realtime</type>
  </service>
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

subtest 'GET reports' => sub {
    my $res;
    stderr_is {
        $res = $endpoint->run_test_request(
            GET => '/requests.xml?jurisdiction_id=dummy&start_date=2018-04-17T00:00:00Z&end_date=2018-04-18T00:00:00Z',
        );
    } "no easting/northing for Enquiry 2004\nno easting/northing for Enquiry 2005\n", 'Warnings about invalid locations output';
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
  <request>
    <address></address>
    <address_id></address_id>
    <description>this is another report from confirm</description>
    <lat>100</lat>
    <long>100</long>
    <media_url></media_url>
    <requested_datetime>2018-04-17T13:34:56+01:00</requested_datetime>
    <service_code>GHI_JKL</service_code>
    <service_name>Graffiti</service_name>
    <service_request_id>2006</service_request_id>
    <status>in_progress</status>
    <updated_datetime>2018-04-17T13:34:56+01:00</updated_datetime>
    <zipcode></zipcode>
  </request>
</service_requests>
XML

    is_string $res->content, $expected, 'xml string ok'
    or diag $res->content;
};

done_testing;
