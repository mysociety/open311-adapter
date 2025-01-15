=head1 NAME

Integrations::Agile

=head1 DESCRIPTION

This module provides an interface to the Agile Applications API

https://agileapplications.co.uk/

=cut

package Integrations::Agile;

use strict;
use warnings;

use HTTP::Request;
use JSON::MaybeXS;
use LWP::UserAgent;
use Moo;

with 'Role::Config';
with 'Role::Logger';

has ua => (
    is      => 'lazy',
    default => sub {
        LWP::UserAgent->new( agent => 'FixMyStreet/open311-adapter' );
    },
);

sub api_call {
    my ( $self, %args ) = @_;

    my $action = $args{action};
    my $controller = $args{controller};
    my $data = $args{data};
    my $method = 'POST';

    my $body = {
        Method     => $method,
        Controller => $controller,
        Action     => $action,
        Data       => $data,
    };
    my $body_json = encode_json($body);

    my $uri = URI->new( $self->config->{url} );

    my $req = HTTP::Request->new( $method, $uri );
    $req->content_type('application/json; charset=UTF-8');
    $req->content($body_json);

    $self->logger->debug($action);
    $self->logger->debug($body_json);

    my $res = $self->ua->request($req);

    if ( $res->is_success ) {
        $self->logger->debug( $res->content );
        return decode_json( $res->content );

    } else {
        $self->logger->error($action);
        $self->logger->error($body_json);
        $self->logger->error( $res->content );
        die $res->content;
    }
}

sub IsAddressFree {
    my ( $self, $uprn ) = @_;

    return $self->api_call(
        action     => 'isaddressfree',
        controller => 'customer',
        data       => { UPRN => $uprn },
    );
}

sub SignUp {
    my ( $self, $params ) = @_;

    return $self->api_call(
        action     => 'signup',
        controller => 'customer',
        data       => $params,
    );
}

1;
