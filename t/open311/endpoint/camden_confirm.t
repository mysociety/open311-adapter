use strict;
use warnings;

BEGIN { $ENV{TEST_MODE} = 1; }

use Test::More;
use Test::MockModule;
use Path::Tiny;

my $confirm_integ = Test::MockModule->new('Integrations::Confirm');
$confirm_integ->mock(config => sub {
    {
        endpoint_url => 'http://www.example.org/',
    }
});

$confirm_integ->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'ABC', ServiceName => 'Trees', EnquirySubject => [ { SubjectCode => "DEF" } ] },
            ] } }
        };
    }
    return {};
});

use_ok 'Open311::Endpoint::Integration::UK::Camden::ConfirmTrees';

my $endpoint = Open311::Endpoint::Integration::UK::Camden::ConfirmTrees->new(
    config_file => path(__FILE__)->sibling("camden_confirm_trees.yml")->stringify,
);

subtest "GET Service List" => sub {

my $res = $endpoint->run_test_request( GET => '/services.xml' );
    ok $res->is_success, 'xml success';
    my $expected = <<XML;
<?xml version="1.0" encoding="utf-8"?>
<services>
  <service>
    <description>Blocking streetlight</description>
      <groups>
       <group>Trees</group>
      </groups>
      <keywords></keywords>
      <metadata>true</metadata>
      <service_code>ABC_DEF</service_code>
      <service_name>Blocking streetlight</service_name>
      <type>realtime</type>
   </service>
   <service>
    <description>Blocking traffic signal/sign</description>
    <groups>
     <group>Trees</group>
    </groups>
    <keywords></keywords>
    <metadata>true</metadata>
    <service_code>ABC_DEF_1</service_code>
    <service_name>Blocking traffic signal/sign</service_name>
    <type>realtime</type>
   </service>
</services>
XML
    my $content = $res->content;
    $content =~ s/\s+//g;
    $expected =~ s/\s+//g;
    is $content, $expected
        or diag $res->content;
};

subtest process_service_request_args => sub {
    my $args = {
        attributes => {
            description => 'Tree overhanging garden fence and blocking light',
            fixmystreet_id => '2157',
            location       => 'Opposite post office',
            report_url => 'http://camden.example.org/report/2157',
            closest_address => '1 High Street, Town Centre',
        },
        service_code => 'ABC_DEF',
    };

    is $endpoint->process_service_request_args($args)->{location}, 'Opposite post office; 1 High Street, Town Centre', 'Nearest address combined into location field';
};

done_testing;
