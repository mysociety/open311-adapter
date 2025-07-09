package Integrations::Confirm::Dummy;
use Path::Tiny;
use Moo;
extends 'Integrations::Confirm';
sub _build_config_file { path(__FILE__)->sibling("confirm.yml")->stringify }

package main;

use strict;
use warnings;

use Test::More;
use Test::MockModule;
use Test::Output;
use HTTP::Response;
use JSON::MaybeXS;

BEGIN { $ENV{TEST_MODE} = 1; }

my $lwp = Test::MockModule->new('LWP::UserAgent');

$lwp->mock(request => sub {
    return HTTP::Response->new(200, 'OK', [], encode_json({
            data => {},
            errors => [
                {
                    message => "Uh-oh spaghettio!",
                }
            ]
        })
    );
});

my $integration = Integrations::Confirm::Dummy->new;

subtest "GraphQL errors are logged " => sub {
    local $ENV{TEST_LOGGER} = 'warn';
    stderr_like {
        $integration->perform_request_graphql(type => 'job_types');
    } qr/.*Uh-oh spaghettio!.*/, 'Got expected warning log for errors.';
};

subtest "Custom GraphQL query can be passed in" => sub {
    my $custom_query = 'query { customTest { id name } }';

    my $sent_request;
    $lwp->mock(request => sub {
        is(decode_json($_[1]->content)->{query}, $custom_query, 'Custom GraphQL query was sent in request');
        return HTTP::Response->new(200, 'OK', [], encode_json({
            data => { customTest => [{ id => 1, name => 'test' }] }
        }));
    });

    $integration->perform_request_graphql(query => $custom_query);
};

done_testing;
