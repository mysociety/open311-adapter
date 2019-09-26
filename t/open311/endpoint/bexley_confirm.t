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
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("bexley_confirm.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::Confirm::Bexley::Dummy');
sub jurisdiction_id { return 'dummy'; }

package main;

use strict;
use warnings;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::Output;

use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm::Bexley');
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
        foreach (${$op->value}->value) {
            is $_->value, 999999 if $_->name eq 'SiteCode';
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
        return { OperationResponse => { GetEnquiryStatusChangesResponse => { UpdatedEnquiry => [
            { EnquiryNumber => 2001, EnquiryStatusLog => [ { EnquiryLogNumber => 3, LogEffectiveTime => '2018-03-01T12:00:00Z', LoggedTime => '2018-03-01T12:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 1, LogEffectiveTime => '2018-03-01T13:00:00Z', LoggedTime => '2018-03-01T13:00:00Z', EnquiryStatusCode => 'INP' } ] },
            { EnquiryNumber => 2002, EnquiryStatusLog => [ { EnquiryLogNumber => 2, LogEffectiveTime => '2018-01-17T12:34:56Z', LoggedTime => '2018-03-01T13:30:00.4000Z', EnquiryStatusCode => 'DUP' } ] },
        ] } } };
    }
    return {};
});

use Open311::Endpoint::Integration::UK::Bexley::Confirm::Dummy;

my $endpoint = Open311::Endpoint::Integration::UK::Bexley::Confirm::Dummy->new(
    jurisdiction_id => 'dummy',
    config_file => path(__FILE__)->sibling("bexley_confirm.yml")->stringify,
);

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
</services>
XML
    is $res->content, $expected
        or diag $res->content;
};

done_testing;
