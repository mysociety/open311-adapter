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
use Test::MockModule;

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
    }
    return {};
});

use Open311::Endpoint::Integration::UK::Bexley::Confirm::Dummy;

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

done_testing;
