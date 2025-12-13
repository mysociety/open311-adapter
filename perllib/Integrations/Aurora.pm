=head1 NAME

Integrations::Aurora

=head1 DESCRIPTION

This module provides an interface to the Aurora Cases API

https://cases.aurora.symology.net/swagger/index.html

=cut

package Integrations::Aurora;

use strict;
use warnings;

use HTTP::Request::Common;
use JSON::MaybeXS;
use LWP::UserAgent;
use Moo;
use MIME::Base64 qw(decode_base64);

with 'Role::Config';
with 'Role::Logger';
with 'Role::Memcached';

=head1 CONFIGURATION

=cut

=head2 oauth

We fetch an access token from Aurora's identity service via
an OAuth password grant.

The required fields in the config under 'oauth' are:
* username
* password
* client_id
* client_secret
* access_token_url

=cut

has oauth => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth} }
);

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);

has access_token => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $token = $self->memcache->get('access_token');
        unless ($token) {
            my $response = $self->ua->request(POST $self->oauth->{access_token_url},
                 [
                    grant_type => 'password',
                    scope => "Symology.Aurora.Customer.Api.User",
                    username => $self->oauth->{username},
                    password => $self->oauth->{password},
                    client_id => $self->oauth->{client_id},
                    client_secret => $self->oauth->{client_secret},
                ]
            );
            unless ($response->is_success) {
                $self->logger->warn("Getting OAuth access token failed.");
                return;
            }
            my $content = decode_json($response->content);
            $token = $content->{access_token};
            $self->memcache->set('access_token', $token, time() + $content->{expires_in});
        }
        return $token;
    },
);

1;
