package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';

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

package main;

use strict; use warnings;

use utf8;

use Test::More;
use Test::LongString;
use Test::MockModule;
use Test::MockTime ':all';

use Path::Tiny;
use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;

use Open311::Endpoint::Integration::UK;
use Integrations::WDM;

my $endpoint = Open311::Endpoint::Integration::UK->new;

my %responses = (
    'SOAP CreateEnquiry' => '
        <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
          <soap:Body>
            <CreateEnquiryResponse xmlns="http://www.wdm.co.uk/remedy/">
              <CreateEnquiryResult>OK</CreateEnquiryResult>
            </CreateEnquiryResponse>
          </soap:Body>
        </soap:Envelope>
    ',
);

my @sent;

my $integration = Test::MockModule->new('Integrations::WDM');

$integration->mock('_soap_call', sub {
    my ($self, $url, $method, $data) = @_;

    my $x = SOAP::Serializer->new();
    my ($content, $name) = ( $data, 'data' );
    if ( ref($data) eq 'SOAP::Data' ) {
        $content = ${$data->value}->value;
        $name = $data->name;
    } elsif ( ref($data) eq 'ARRAY' ) {
        $content = $x->envelope( method => $method, @$data );
    }
    push @sent, { method => $method, name => $name, content => $content };
    #warn $responses{"SOAP $method"};
    my $som = SOAP::Deserializer->deserialize($responses{"SOAP $method"});
    return $som;
});

my $ox_integration = Test::MockModule->new('Integrations::WDM::Oxfordshire');
$ox_integration->mock('_build_config_file', sub {
    path(__FILE__)->sibling('oxfordshire.yml');
});

my %defaults = (
    fms_id => 1,
    firstname => 'Bob',
    lastname => 'Mould',
    address_string => '22 Acacia Avenue',
    email => 'test@example.com',
    description => 'description',
    latitude => 50,
    longitude => 0.1,
    easting => 99,
    northing => 101,
    usrn => 48405113,
    category => 'POT',
    category_code => '',
    category_detail => 'POT',
    category_type => '',
);

for my $test (
    {
        test_desc => 'create basic problem',
    },
    {
        test_desc => 'create problem with no usrn',
        usrn => undef,
    },
) {
    subtest $test->{test_desc} => sub {
        set_fixed_time('2014-01-01T12:00:00Z');
        my $args = {
            %defaults,
            %$test,
        };
        my %post_args = (
            jurisdiction_id => 'oxfordshire',
            api_key => 'test',
            service_code => $args->{category},
            address_string => $args->{address_string},
            first_name => $args->{firstname},
            last_name => $args->{lastname},
            email => $args->{email},
            description => $args->{description},
            lat => $args->{latitude},
            long => $args->{longitude},
            'attribute[description]' => $args->{description},
            'attribute[external_id]' => $args->{fms_id},
            'attribute[easting]' => $args->{easting},
            'attribute[northing]' => $args->{northing},
        );

        $post_args{ 'attribute[usrn]' } = $args->{usrn} if $args->{usrn};
        my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

        my $sent = pop @sent;
        ok $res->is_success, 'valid request'
            or diag $res->content;


        is $sent->{content}, _generate_request_xml($args), 'correct xml sent';

        is_deeply decode_json($res->content),
            [ {
                "service_request_id" => $args->{fms_id}
            } ], 'correct json returned';

    };
}

subtest "check time uses London time" => sub {
    set_fixed_time('2018-08-01T12:00:00Z');
    my $args = {
        %defaults,
    };
    my %post_args = (
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_code => $args->{category},
        address_string => $args->{address_string},
        first_name => $args->{firstname},
        last_name => $args->{lastname},
        email => $args->{email},
        description => $args->{description},
        lat => $args->{latitude},
        long => $args->{longitude},
        'attribute[description]' => $args->{description},
        'attribute[external_id]' => $args->{fms_id},
        'attribute[easting]' => $args->{easting},
        'attribute[northing]' => $args->{northing},
        'attribute[usrn]' => $args->{usrn},
    );

    my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    $args->{time} = '2018-08-01 13:00:00';
    is $sent->{content}, _generate_request_xml($args), 'correct xml sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => $args->{fms_id}
        } ], 'correct json returned';

};

for my $category (
    (
        'BR',
        'Row',
        'DR',
        'VG',
        'SP',
        'OT',
        'F D',
        'PT',
        'CD',
        'SN',
        'TLT',
        'TR',
    )
) {
    subtest "check posting with category $category" => sub {
        set_fixed_time('2014-01-01T12:00:00Z');
        my $args = {
            %defaults,
            (
                category => $category,
                category_detail => $category,
            )
        };
        my %post_args = (
            jurisdiction_id => 'oxfordshire',
            api_key => 'test',
            service_code => $category,
            address_string => $args->{address_string},
            first_name => $args->{firstname},
            last_name => $args->{lastname},
            email => $args->{email},
            description => $args->{description},
            lat => $args->{latitude},
            long => $args->{longitude},
            'attribute[description]' => $args->{description},
            'attribute[external_id]' => $args->{fms_id},
            'attribute[easting]' => $args->{easting},
            'attribute[northing]' => $args->{northing},
            'attribute[usrn]' => $args->{usrn},
        );

        my $res = $endpoint->run_test_request( POST => '/requests.json', %post_args );

        my $sent = pop @sent;
        ok $res->is_success, 'valid request'
            or diag $res->content;

        is $sent->{content}, _generate_request_xml($args), 'correct xml sent';
    }
}

subtest "create problem with multiple photos" => sub {
    set_fixed_time('2014-01-01T12:00:00Z');
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'oxfordshire',
        api_key => 'test',
        service_code => 'POT',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[description]' => 'description',
        'attribute[external_id]' => '1',
        'attribute[easting]' => '99',
        'attribute[northing]' => '101',
        'attribute[usrn]' => '48405113',
        media_url => 'http://photo1.com',
        media_url => 'http://photo2.com',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;


    is $sent->{content},
    '<wdmenquiry>
  <comments>description</comments>
  <customer_details>
    <email>test@example.com</email>
    <name>
      <firstname>Bob</firstname>
      <lastname>Mould</lastname>
    </name>
    <telephone_number></telephone_number>
  </customer_details>
  <documents>
    <URL>http://photo1.com</URL>
    <URL>http://photo2.com</URL>
  </documents>
  <easting>99</easting>
  <enquiry_category_code></enquiry_category_code>
  <enquiry_detail_code>POT</enquiry_detail_code>
  <enquiry_reference></enquiry_reference>
  <enquiry_source>FixMyStreet</enquiry_source>
  <enquiry_time>2014-01-01 12:00:00</enquiry_time>
  <enquiry_type_code></enquiry_type_code>
  <external_system_reference>1</external_system_reference>
  <location>
    <item_uid></item_uid>
    <placename>22 Acacia Avenue</placename>
  </location>
  <northing>101</northing>
  <usrn>48405113</usrn>
</wdmenquiry>
',
    'correct xml sent';

    is_deeply decode_json($res->content),
        [ {
            "service_request_id" => 1
        } ], 'correct json returned';
};


sub _generate_request_xml {
    my $args = shift;

    $args->{usrn} //= 0;
    $args->{phone} //= '';
    $args->{time} //= '2014-01-01 12:00:00';

    return "<wdmenquiry>
  <comments>$args->{description}</comments>
  <customer_details>
    <email>$args->{email}</email>
    <name>
      <firstname>$args->{firstname}</firstname>
      <lastname>$args->{lastname}</lastname>
    </name>
    <telephone_number>$args->{phone}</telephone_number>
  </customer_details>
  <easting>$args->{easting}</easting>
  <enquiry_category_code>$args->{category_code}</enquiry_category_code>
  <enquiry_detail_code>$args->{category_detail}</enquiry_detail_code>
  <enquiry_reference></enquiry_reference>
  <enquiry_source>FixMyStreet</enquiry_source>
  <enquiry_time>$args->{time}</enquiry_time>
  <enquiry_type_code>$args->{category_type}</enquiry_type_code>
  <external_system_reference>$args->{fms_id}</external_system_reference>
  <location>
    <item_uid></item_uid>
    <placename>$args->{address_string}</placename>
  </location>
  <northing>$args->{northing}</northing>
  <usrn>$args->{usrn}</usrn>
</wdmenquiry>
";
}

restore_time();
done_testing;