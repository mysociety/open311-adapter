use strict;
use warnings;

package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'confirm_attributes';
    $args{config_data} = '
service_whitelist:
  Roads:
    HM_PHS: Small pothole
    HM_PHL: Large pothole
ignored_attributes:
  - IGN
ignored_attribute_options:
  - PS
attribute_descriptions:
  QUES2: "Better question text"
attribute_value_overrides:
  QUES:
    "do not use": "use instead"
';
    return $class->$orig(%args);
};

package main;

use Test::More;
use Test::LongString;
use Test::MockModule;

BEGIN { $ENV{TEST_MODE} = 1; }

my $open311 = Test::MockModule->new('Integrations::Confirm');
$open311->mock(perform_request => sub {
    my ($self, $op) = @_; # Don't care about subsequent ops
    $op = $$op;
    if ($op->name && $op->name eq 'GetEnquiryLookups') {
        return {
            OperationResponse => { GetEnquiryLookupsResponse => { TypeOfService => [
                { ServiceCode => 'HM', ServiceName => 'Highways', EnquirySubject => [ {
                    SubjectCode => "PHS",
                    SubjectAttribute => [
                        { EnqAttribTypeCode => 'QUES', },
                        { EnqAttribTypeCode => 'QUES2', },
                        { EnqAttribTypeCode => 'IGN', },
                    ],
                } ] },
                { ServiceCode => 'HM', ServiceName => 'Highways', EnquirySubject => [ { SubjectCode => "PHL" } ] },
            ],
            EnquiryAttributeType => [
                { EnqAttribTypeCode => 'QUES', MandatoryFlag => 'true', EnqAttribTypeName => 'Question?',
                  EnquiryAttributeValue => [
                      { EnqAttribValueCode => 'PS', EnqAttribValueName => 'Please select' },
                      { EnqAttribValueCode => 'Y', EnqAttribValueName => 'Yes' },
                      { EnqAttribValueCode => 'N', EnqAttribValueName => 'No' },
                      { EnqAttribValueCode => 'DK', EnqAttribValueName => 'do not use' },
                  ] },
                { EnqAttribTypeCode => 'QUES2', MandatoryFlag => 'false', EnqAttribTypeName => 'Bad question',
                  EnquiryAttributeValue => [] },
                { EnqAttribTypeCode => 'IGN', MandatoryFlag => 'false', EnqAttribTypeName => 'Ignored question' },
            ],
            } }
        };
    }
    return {};
});
$open311->mock(endpoint_url => sub { 'http://example.org/' });

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

subtest "GET wrapped Service List Description" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/HM_PHS.xml' );
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
      <code>QUES</code>
      <datatype>singlevaluelist</datatype>
      <datatype_description></datatype_description>
      <description>Question?</description>
      <order>11</order>
      <required>true</required>
      <values>
        <value>
          <name>use instead</name>
          <key>DK</key>
        </value>
        <value>
          <name>No</name>
          <key>N</key>
        </value>
        <value>
          <name>Yes</name>
          <key>Y</key>
        </value>
      </values>
      <variable>true</variable>
    </attribute>
    <attribute>
      <code>QUES2</code>
      <datatype>string</datatype>
      <datatype_description></datatype_description>
      <description>Better question text</description>
      <order>12</order>
      <required>false</required>
      <variable>true</variable>
    </attribute>
  </attributes>
  <service_code>HM_PHS</service_code>
</service_definition>
XML
    print $res->content;
    is_string $res->content, $expected;
};

done_testing;
