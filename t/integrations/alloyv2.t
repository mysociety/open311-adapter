package Integrations::AlloyV2::Dummy;
use Moo;

extends 'Integrations::AlloyV2';
sub _build_config_file { path(__FILE__)->sibling("alloyv2.yml")->stringify }

package main;

use strict;
use warnings;
use utf8;

use Test::More;
use Test::MockModule;
use Encode;
use JSON::MaybeXS;
use Path::Tiny;

my $integration = Integrations::AlloyV2::Dummy->new;
my $mocked_integration = Test::MockModule->new('Integrations::AlloyV2');
$mocked_integration->mock('api_call', sub {
    my ($self, %args) = @_;
    my $call = $args{call};
    if ($call =~ 'aqs/join') {
        return decode_json(encode_utf8(path(__FILE__)->sibling('json/alloyv2/join_response.json')->slurp));
    }
    fail "Got unexpected call: $call";
});

subtest "Join results are parsed correctly" => sub {
    my $query = {
        properties => {
            joinAttributes => [ 'root^parent_attribute.child_attribute' ]
        }
    };
    my $res = $integration->search($query, 1);
    is_deeply $res, [
        {
            'attributes' => [
                {
                    'attributeCode' => 'normal_attribute',
                    'value' => 'n1'
                },
                {
                    'attributeCode' => 'root.parent_attribute.child_attribute',
                    'value' => 'c1'
                }
            ],
            'itemId' => 'r1',
            'joinedItemIDs' => ['p1']
        },
        {
            'itemId' => 'r2',
            'attributes' => [
                {
                    'value' => 'n2',
                    'attributeCode' => 'normal_attribute'
                }
            ]
        }
    ];
};

done_testing;
