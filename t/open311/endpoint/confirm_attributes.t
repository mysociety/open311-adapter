use strict;
use warnings;

package Open311::Endpoint::Integration::UK::Dummy;
use Moo;
extends 'Open311::Endpoint::Integration::Confirm';
around BUILDARGS => sub {
my %test_config = (
  'ignored_attributes' => '
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
    ',
  'allowed_attributes' => '
    service_whitelist:
      Roads:
        HM_PHS: Small pothole
        HM_PHL: Large pothole
    ignored_attributes:
      - QUES
    allowed_attributes:
      - QUES
      - QUES2
      - SINC
    ignored_attribute_options:
      - PS
    attribute_descriptions:
      QUES2: "Better question text"
    attribute_value_overrides:
      QUES:
        "do not use": "use instead"
    ',
  'include_none' => '
    service_whitelist:
      Roads:
        HM_PHS: Small pothole
        HM_PHL: Large pothole
    allowed_attributes: []
    ',
);
    my ($orig, $class, %args) = @_;

    $args{jurisdiction_id} = 'confirm_attributes';
    $args{config_data} = $test_config{ $args{test_config} };
    return $class->$orig(%args);
};

package main;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Path::Tiny;

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
                        { EnqAttribTypeCode => 'SINC', },
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
                { EnqAttribTypeCode => 'SINC', MandatoryFlag => 'false', EnqAttribTypeName => 'Abandoned since', EnqAttribTypeFlag => 'D' },
            ],
            } }
        };
    }
    return {};
});
$open311->mock(endpoint_url => sub { 'http://example.org/' });

my $endpoint;

for my $test ('ignored_attributes', 'allowed_attributes') {

  $endpoint = Open311::Endpoint::Integration::UK::Dummy->new(test_config => $test);

  subtest "GET wrapped Service List Description" => sub {
      my $res = $endpoint->run_test_request( GET => '/services/HM_PHS.xml' );
      ok $res->is_success, 'xml success';
      my $expected = path(__FILE__)->sibling('xml/confirm/service_without_ign_attribute.xml')->slurp;
      print $res->content;
      is_string $res->content, $expected;
  };
};

$endpoint = Open311::Endpoint::Integration::UK::Dummy->new(test_config => 'include_none');

subtest "GET wrapped Service List Description with empty allowed_attributes" => sub {
    my $res = $endpoint->run_test_request( GET => '/services/HM_PHS.xml' );
    ok $res->is_success, 'xml success';
    my $expected = path(__FILE__)->sibling('xml/confirm/service_without_any_attributes.xml')->slurp;
    print $res->content;
    is_string $res->content, $expected;
};

done_testing;
