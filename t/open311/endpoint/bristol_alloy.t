package Integrations::AlloyV2::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("bristol_alloy.yml")->stringify }

package Open311::Endpoint::Integration::UK::Dummy;
use Path::Tiny;
use Moo;
extends 'Open311::Endpoint::Integration::UK::Bristol::Alloy';
around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'dummy';
    $args{config_file} = path(__FILE__)->sibling("bristol_alloy.yml")->stringify;
    return $class->$orig(%args);
};
has integration_class => (is => 'ro', default => 'Integrations::AlloyV2::Dummy');

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use Open311::Endpoint;

BEGIN { $ENV{TEST_MODE} = 1; }

my $endpoint = Open311::Endpoint::Integration::UK::Dummy->new;

my (@sent);

my $alloy_endpoint = Test::MockModule->new('Open311::Endpoint::Integration::AlloyV2');

my $integration = Test::MockModule->new('Integrations::AlloyV2');
$integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    my $params = $args{params};
    my $body = $args{body};
    my $is_file = $args{is_file};
    push @sent, $body if $body;

    my $content = undef;

    if ($body && $call =~ 'aqs/statistics') {
        $content = path(__FILE__)->sibling("json/alloyv2/bristol_categories_count_response.json")->slurp;
    } elsif ($body && $call =~ 'aqs/query') {
        my $designCode = $body->{aqs}->{properties}->{dodiCode};
        my @search_params = @{$body->{aqs}->{children}->[0]->{children}};
        my ($attribute) = grep { $_->{type} eq 'Attribute' } @search_params;
        my ($search) = grep { $_->{type} eq 'String' } @search_params;
        if ($designCode eq 'designs_streetCleansingNetwork_5ddbe68aca315006c08f4097') {
            $content = path(__FILE__)->sibling("json/alloyv2/bristol_usrn_search_response.json")->slurp;
        } elsif ($designCode eq 'designs_locality_5e16f845ca3150037850b67a') {
            $content = path(__FILE__)->sibling("json/alloyv2/bristol_locality_search_response.json")->slurp;
        };
    } elsif ($body && $call =~ 'item') {
        $content = path(__FILE__)->sibling("json/alloyv2/bristol_create_report_response.json")->slurp;
    } elsif (!$content) {
        warn "No handler found for API call " . $call . "  " . encode_json($body);
        return decode_json('[]');
    }

    return decode_json(encode_utf8($content));
});


subtest "check service group and category aliases" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=dummy',
    );
    is_deeply decode_json($res->content),
    [
          {
            'keywords' => '',
            'description' => 'Fly posting',
            'groups' => [
                          ''
                        ],
            'service_code' => 'SC-Fly-Post_Defect_1',
            'service_name' => 'Fly posting',
            'metadata' => 'true',
            'type' => 'realtime'
          },
          {
            'groups' => [
                          ''
                        ],
            'type' => 'realtime',
            'service_name' => 'Flytipping',
            'metadata' => 'true',
            'description' => 'Flytipping',
            'keywords' => '',
            'service_code' => 'SC-Fly-Tip_Defect_1'
          },
          {
            'groups' => [
                          ''
                        ],
            'keywords' => '',
            'description' => 'Graffiti',
            'service_name' => 'Graffiti',
            'metadata' => 'true',
            'type' => 'realtime',
            'service_code' => 'SC-Graffiti_Defect_1'
          },
          {
            'service_name' => 'Bin overflowing',
            'metadata' => 'true',
            'type' => 'realtime',
            'service_code' => 'Bin_overflowing',
            'groups' => [
                          'Street cleansing'
                        ],
            'keywords' => '',
            'description' => 'Bin overflowing'
          },
          {
            'type' => 'realtime',
            'groups' => [
                          'Street cleansing'
                        ],
            'metadata' => 'true',
            'service_name' => 'Blood',
            'description' => 'Blood',
            'keywords' => '',
            'service_code' => 'Blood'
          },
          {
            'service_code' => 'Dead_animal',
            'metadata' => 'true',
            'service_name' => 'Dead animal',
            'type' => 'realtime',
            'keywords' => '',
            'description' => 'Dead animal',
            'groups' => [
                          'Street cleansing'
                        ]
          },
          {
            'metadata' => 'true',
            'service_name' => 'Dog fouling',
            'groups' => [
                          'Street cleansing'
                        ],
            'type' => 'realtime',
            'service_code' => 'Dog_fouling',
            'keywords' => '',
            'description' => 'Dog fouling'
          }
        ];
};

my %shared_params = (
    jurisdiction_id => 'dummy',
    api_key => 'test',
    first_name => 'David',
    last_name => 'Anthony',
    email => 'test@example.com',
    description => 'description',
    lat => '50',
    long => '0.1',
    'attribute[description]' => 'description',
    'attribute[title]' => 'title',
    'attribute[report_url]' => 'http://localhost/123',
    'attribute[fixmystreet_id]' => 123,
    'attribute[easting]' => 1,
    'attribute[northing]' => 2,
    'attribute[usrn]' => '1234567',
);

for my $test (
    {
        title => "Graffiti report",
        extra_params => {
            'attribute[SizeOfIssue]' => '2',
            'attribute[Offensive]' => '0',
            'attribute[Private]' => '1',
            'attribute[PropertyType]' => '1',
            'attribute[SurfaceType]' => '3',
            'attribute[Height]' => '1',
            'attribute[category]' => 'Graffiti',
            'service_code' => 'SC-Graffiti_Defect_1',
        },
        expected => {
            'attributes_bWCSCGraffitiDefectSizeOfIssue_5e2035adca315009b4e5bc0d' => ['5e1f1bffca31500c541f82d8'],
            'attributes_bWCSCGraffitiDefectIsItOffensive_5dfa42edca31500418946fc8' => JSON->false,
            'attributes_bWCSCGraffitiDefectPrivateLand_5dfa4398ca31500d9808ecfb' => JSON->true,
            'attributes_bWCSCGraffitiDefectPropertyType_5e20358dca315009b4e5bc08' => ['5e1f3ad1ca31500b78e78c3f'],
            'attributes_bWCSCGraffitiDefectSurface_5e204149ca31501354c02803' => ['5e203bb0ca31500a180d3d26'],
            'attributes_bWCSCGraffitiDefectHeight_5e204239ca315012d094d706' => ['5e203e6eca315012d094d5f3'],
            'attributes_bWCSCGraffitiDefectLocationDescription_5dfa4406ca31500d9808ed27' => 'description',
            'attributes_bWCSCGraffitiDefectLocality_5e6f97e54cee260f780bf4e6' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCGraffitiDefect_5dfa4261ca31500cec4147de',
    },
    {
        title => "Flyposting report",
        extra_params => {
            'attribute[SizeOfIssue]' => '2',
            'attribute[Offensive]' => '0',
            'attribute[Private]' => '1',
            'attribute[PropertyType]' => '1',
            'attribute[SurfaceType]' => '3',
            'attribute[Height]' => '0',
            'attribute[category]' => 'Fly posting',
            'service_code' => 'SC-Fly-Post_Defect_1',
        },
        expected => {
            'attributes_bWCSCFlyPostDefectSizeOfIssue_5e203bfeca31501354c02576' => ['5e1f1bffca31500c541f82d8'],
            'attributes_bWCSCFlyPostDefectIsItOffensive_5e203c6fca315009b4e5c756' => JSON->false,
            'attributes_bWCSCFlyPostDefectPrivateProperty_5e203c9aca315009b4e5c76f' => JSON->true,
            'attributes_bWCSCFlyPostDefectPropertyType_5e203c33ca315009b4e5c742' => ['5e1f3ad1ca31500b78e78c3f'],
            'attributes_bWCSCFlyPostDefectSurfaceType_5e203d32ca315012d094d511' => ['5e203bb0ca31500a180d3d26'],
            'attributes_bWCSCFlyPostDefectHeight_5e203f18ca31500a180d3f86' => ['5e203e36ca315012d094d5b7'],
            'attributes_bWCSCFlyPostDefectFullDetails_5e203cd5ca315012d094d4eb' => 'description',
            'attributes_bWCSCFlyPostDefectLocality_5e6f97874cee260f90aca0d0' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCFlyPostDefect_5e203bd4ca315009b4e5c714',
    },
    {
        title => "Flytipping report",
        extra_params => {
            'attribute[SizeOfIssue]' => '2',
            'attribute[Health]' => JSON->false,
            'attribute[Witness]' => JSON->false,
            'attribute[Hazardous]' => JSON->true,
            'attribute[category]' => 'Fly tipping',
            'service_code' => 'SC-Fly-Tip_Defect_1',
        },
        expected => {
            'attributes_bWCSCFlyTipDefectSizeOfIssue_5e20654dca315012d094f4b9' => ['5e1f1bffca31500c541f82d8'],
            'attributes_bWCSCFlyTipDefectAffectingPublicHealthSafety_5e20604fca31500a180d5b98' => JSON->false,
            'attributes_bWCSCFlyTipDefectHazardousSubstance_5e206019ca315012d094f293' => JSON->true,
            'attributes_bWCSCFlyTipDefectEvidenceLikely_5dfa156cca31500ee80ea93c' => JSON->false,
            'attributes_bWCSCFlyTipDefectLocationDescription_5dfa16deca31500ee80ea988' => 'description',
            'attributes_bWCSCFlyTipDefectLocality_5e6f97c54cee260f780bf4e1' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCFlyTipDefect_5dfa127dca31500ee80ea8df',
    },
    {
        title => "Dog fouling report",
        extra_params => {
            'attribute[SizeOfIssue]' => '2',
            'attribute[category]' => 'Dog fouling',
            'service_code' => 'Dog_fouling',
        },
        expected => {
            'attributes_bWCSCStreetCleansingDefectSizeOfIssue_5e21b5ccca31500d1c836be0' => ['5e1f1bffca31500c541f82d8'],
            'attributes_bWCSCStreetCleansingDefectJobType_5e21b5adca31500d1c836bc9' => ['5e2179a3ca315012d0956667'],
            'attributes_bWCSCStreetCleansingDefectFullDetails_5e21b587ca31500cc0a2df3a' => 'description',
            'attributes_bWCSCStreetCleansingDefectLocality_5e6f97fe4cee260f90aca0d6' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCStreetCleansingDefect_5e21a98bca315003e0983035',
    },
    {
        title => "Blood report",
        extra_params => {
            'attribute[SizeOfIssue]' => '1',
            'attribute[category]' => 'Blood',
            'service_code' => 'Blood',
        },
        expected => {
            'attributes_bWCSCStreetCleansingDefectSizeOfIssue_5e21b5ccca31500d1c836be0' => ['5e1f1bf0ca31500c541f82cb'],
            'attributes_bWCSCStreetCleansingDefectJobType_5e21b5adca31500d1c836bc9' => ['5e21782dca315003e09804a2'],
            'attributes_bWCSCStreetCleansingDefectFullDetails_5e21b587ca31500cc0a2df3a' => 'description',
            'attributes_bWCSCStreetCleansingDefectLocality_5e6f97fe4cee260f90aca0d6' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCStreetCleansingDefect_5e21a98bca315003e0983035',
    },
    {
        title => "Dead cow report",
        extra_params => {
            'attribute[SizeOfIssue]' => '1',
            'attribute[TypeOfAnimal]' => '1',
            'attribute[category]' => 'Dead animal',
            'service_code' => 'Dead_animal',
        },
        expected => {
            'attributes_bWCSCStreetCleansingDefectSizeOfIssue_5e21b5ccca31500d1c836be0' => ['5e1f1bf0ca31500c541f82cb'],
            'attributes_bWCSCStreetCleansingDefectJobType_5e21b5adca31500d1c836bc9' => ['5e21a679ca31500d1c836901'],
            'attributes_bWCSCStreetCleansingDefectFullDetails_5e21b587ca31500cc0a2df3a' => 'description',
            'attributes_bWCSCStreetCleansingDefectLocality_5e6f97fe4cee260f90aca0d6' => ['5e16fa66ca314f0980300be5'],
        },
        expected_design => 'designs_bWCSCStreetCleansingDefect_5e21a98bca315003e0983035',
    },
) {
    subtest $test->{title} => sub {
        my $res = $endpoint->run_test_request(
            POST => '/requests.json',
            %shared_params,
            %{ $test->{extra_params} },
        );

        ok $res->is_success, 'valid request' or diag $res->content;

        my $sent = pop @sent;
        is $sent->{designCode}, $test->{expected_design}, "Correct designCode selected";
        my %sent_data = map { $_->{attributeCode}, $_->{value} } @{$sent->{attributes}};
        $test->{description} = "Correct attribute populated with correct data";
        for my $key (keys %{$test->{expected}}) {
            if (ref $test->{expected}->{$key} eq 'JSON::PP::Boolean') {
                is $test->{expected}->{$key}, $sent_data{$key}, $test->{description};
            } elsif (ref $test->{expected}->{$key} eq 'ARRAY') {
                is $test->{expected}->{$key}[0], $sent_data{$key}[0], $test->{description};
            } else {
                is $test->{expected}->{$key}, $sent_data{$key}, $test->{description};
            }
        }
    };
}

done_testing;
