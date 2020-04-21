package Mock::Response;

use Moo;
use Encode;
use Types::Standard ':all';
use utf8;

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

use Encode;
use Test::More;
use Test::LongString;
use Test::MockModule;

use Open311::Endpoint;
use Data::Dumper;
use JSON::MaybeXS;
use Path::Tiny;

BEGIN { $ENV{TEST_MODE} = 1; }
use Open311::Endpoint::Integration::SalesForceRest;
use Integrations::SalesForceRest;

my $endpoint = Open311::Endpoint::Integration::SalesForceRest->new( jurisdiction_id => 'eastsussex_salesforce' );

my %responses = (
    'GET Case/describe ' => path(__FILE__)->parent(1)->realpath->child('services.json')->slurp,
    'GET Case/1 ' => path(__FILE__)->parent(1)->realpath->child('case_1.json')->slurp,
    'POST Case ' => '{ "success": true, "id": 1 }',
    'POST Account ' => '{ "success": true, "id": 2 }',
    'GET parameterizedSearch/ q=test@example.com&sobject=Account&Account.fields=PersonEmail' => '{ "searchRecords": [ { "Id": 1 } ] }',
    'GET parameterizedSearch/ q=new@example.com&sobject=Account&Account.fields=PersonEmail' => '{ "searchRecords": [ ] }',
);

my @sent;

my $integration = Test::MockModule->new('Integrations::SalesForceRest');
$integration->mock('_build_config_file', sub {
    path(__FILE__)->sibling('eastsussex.yml');
});
$integration->mock('credentials', sub { 'thisarecredentials' });
$integration->mock('_get_response', sub {
    my ($self, $req) = @_;
    (my $path = $req->uri->path) =~ s{.*sobjects/}{};
    my $key = sprintf '%s %s %s', $req->method, $path, $req->uri->query || '';
    push @sent, $req->content if $key =~ /^POST/;

    my $content = $responses{$key} || '[]';

    my $result = decode_json(encode_utf8($content));
    if ( ref $result eq 'ARRAY' && $result->[0]->{errorCode} ) {
        return Mock::Response->new( is_success => 0, code => 500, content => $content );
    } else {
        return Mock::Response->new( content => $content );
    }
});

subtest "converts validFrom correctly" => sub {
    for my $test (
        {
            in => 'AAAAAAAE',
            out => [45],
        },
        {
            in => 'AAAB',
            #000000000000000000000001
            out => [23],
        },
        {
            in => 'BACAYMAA',
            #000001000000000010000000011000001100000000000000
            out => [5,16,25,26,32,33],
        }
    ) {
        is_deeply Integrations::SalesForceRest::_get_pos($test->{in}), $test->{out}, "converts correctly";
    }
};

subtest "check simple post" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'eastsussex_salesforce',
        api_key => 'test',
        service_code => 'Directional Signs',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[group]' => 'Signs',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($sent), {
        Type => 'Signs',
        Sub_Type__c => 'Directional Signs',
        Description => 'description',
        Latitude => 50,
        Longitude => 0.1,
        Subject => 'Signs',
        CreatedDate => undef,
        Location_Description__c => '22 Acacia Avenue',
        AccountId => 1,
        Origin => 'FMS',
    }, 'correct request sent';

    is_deeply decode_json($res->content), [ { service_request_id => '00123456' } ], 'correct return';
};

subtest "post for a single group item" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'eastsussex_salesforce',
        api_key => 'test',
        service_code => 'Bridges, Walls & Tunnels',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'test@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[group]' => 'Bridges, Walls & Tunnels',
        'attribute[fixmystreet_id]' => 1,
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($sent), {
        Type => 'Bridges, Walls & Tunnels',
        Description => 'description',
        Latitude => 50,
        Longitude => 0.1,
        Subject => 'Bridges, Walls & Tunnels',
        CreatedDate => undef,
        Location_Description__c => '22 Acacia Avenue',
        AccountId => 1,
        Origin => 'FMS',
    }, 'correct request sent';

    is_deeply decode_json($res->content), [ { service_request_id => '00123456' } ], 'correct return';
};

subtest "post that creates an account" => sub {
    my $res = $endpoint->run_test_request(
        POST => '/requests.json',
        jurisdiction_id => 'eastsussex_salesforce',
        api_key => 'test',
        service_code => 'Directional Signs',
        address_string => '22 Acacia Avenue',
        first_name => 'Bob',
        last_name => 'Mould',
        email => 'new@example.com',
        description => 'description',
        lat => '50',
        long => '0.1',
        'attribute[group]' => 'Signs',
        'attribute[fixmystreet_id]' => 1,
    );

    my ($report, $account) = (pop @sent, pop @sent);
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($account), {
        FirstName => 'Bob',
        LastName => 'Mould',
        PersonEmail => 'new@example.com',
        Type => 'Member of Public',
    }, 'correct account sent';

    is_deeply decode_json($report), {
        Type => 'Signs',
        Sub_Type__c => 'Directional Signs',
        Description => 'description',
        Latitude => 50,
        Longitude => 0.1,
        Subject => 'Signs',
        CreatedDate => undef,
        Location_Description__c => '22 Acacia Avenue',
        AccountId => 2,
        Origin => 'FMS',
    }, 'correct request sent';

    is_deeply decode_json($res->content), [ { service_request_id => '00123456' } ], 'correct return';
};

subtest "check fetch service description" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services.json?jurisdiction_id=eastsussex_salesforce',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    [
    {
        service_code => "Abandoned Vehicles",
        service_name => "Abandoned Vehicles",
        description => "Abandoned Vehicles",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Abandoned Vehicle" ]
    },
    {
        service_code => "Advance Warning Sign (VMS)",
        service_name => "Advance Warning Sign (VMS)",
        description => "Advance Warning Sign (VMS)",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Directional Signs",
        service_name => "Directional Signs",
        description => "Directional Signs",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Sign Collection",
        service_name => "Sign Collection",
        description => "Sign Collection",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Sign Posts",
        service_name => "Sign Posts",
        description => "Sign Posts",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Street Name Plates",
        service_name => "Street Name Plates",
        description => "Street Name Plates",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Tourist Signs",
        service_name => "Tourist Signs",
        description => "Tourist Signs",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Village Sign",
        service_name => "Village Sign",
        description => "Village Sign",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Warning Signs",
        service_name => "Warning Signs",
        description => "Warning Signs",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Signs" ]
    },
    {
        service_code => "Bridges, Walls & Tunnels",
        service_name => "Bridges, Walls & Tunnels",
        description => "Bridges, Walls & Tunnels",
        metadata => 'true',
        type => "realtime",
        keywords => "",
        groups => [ "Bridges, Walls & Tunnels" ]
    } ], 'correct json returned';
};

subtest "check fetch service description with no questions" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/Warning Signs.json?jurisdiction_id=eastsussex_salesforce',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "Warning Signs",
        attributes => [
          {
            variable => 'false',
            code => "asset_id",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 1,
            description => "Asset ID",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "group",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 2,
            description => "FixMyStreet Group",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
      ]
    }, 'correct json returned';
};

subtest "check fetch service description with questions" => sub {
    my $res = $endpoint->run_test_request(
      GET => '/services/Tourist Signs.json?jurisdiction_id=eastsussex_salesforce',
    );

    my $sent = pop @sent;
    ok $res->is_success, 'valid request'
        or diag $res->content;

    is_deeply decode_json($res->content),
    {
        service_code => "Tourist Signs",
        attributes => [
          {
            variable => 'false',
            code => "asset_id",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 1,
            description => "Asset ID",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "group",
            datatype => "string",
            required => 'false',
            datatype_description => '',
            order => 2,
            description => "FixMyStreet Group",
            automated => 'hidden_field',
          },
          {
            variable => 'false',
            code => "fixmystreet_id",
            datatype => "string",
            required => 'true',
            datatype_description => '',
            order => 3,
            description => "external system ID",
            automated => 'server_set',
          },
          {
            variable => 'true',
            code => "what_is_the_problem_with_the_sign",
            datatype => "singlevaluelist",
            required => 'false',
            datatype_description => '',
            order => 4,
            description => "What is the problem with the sign?",
            values => [
                {
                    name => "broken",
                    key => "broken",
                },
                {
                    name => "dirty",
                    key => "dirty",
                },
                {
                    name => "sign is incorrect",
                    key => "incorrect",
                }
            ],
          },
      ]
    }, 'correct json returned';
};

done_testing;
