=head1 NAME

Integrations::Surrey::Boomi - Interface to the Surrey Boomi REST API

=cut

package Integrations::Surrey::Boomi;

use strict;
use warnings;

use Moo;
use LWP::UserAgent;
use JSON::MaybeXS;
use Try::Tiny;
use MIME::Base64 qw(encode_base64);


with 'Role::Logger';
with 'Role::Config';

=head1 ATTRIBUTES


=head2 ua

The LWP::UserAgent object used to make requests to the Boomi API.

=cut

has ua => (
    is  => 'rw',
    default => sub {
        my $self = shift;
        my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
        my $hash = encode_base64($self->config->{username} . ':' . $self->config->{password}, "");
        $ua->default_header('Authorization' => "Basic $hash");
        $ua->default_header('Content-Type' => "application/json");
        return $ua;
    },
);

=head1 METHODS

=head2 upsertHighwaysTicket

Create or update a ticket in the Surrey Boomi system.

Returns the ID of the created or updated ticket.

=cut

sub upsertHighwaysTicket {
    my ($self, $ticket) = @_;

    my $resp = $self->post('upsertHighwaysTicket', $ticket);

}


=head2 post

Make a POST request to the Boomi API with the given path and data.

Returns the decoded JSON from the response, if possible, otherwise logs an
error and dies.

=cut

sub post {
    my ($self, $path, $data) = @_;

    my $url = $self->config->{api_url} . $path;
    my $content = encode_json($data);
    $self->logger->debug("[Boomi] Request URL: $url");
    $self->logger->debug("[Boomi] Request content: $content");

    my $response = $self->ua->post(
        $url,
        Content         => $content,
    );

    $self->logger->debug("[Boomi] Response status: " . $response->status_line);
    $self->logger->debug("[Boomi] Response content: " . $response->decoded_content);

    if (!$response->is_success) {
        $self->error("[Boomi] POST request failed: " . $response->status_line);
    }

    try {
        my $content = $response->decoded_content;
        return decode_json($content);
    } catch {
        $self->error("[Boomi] Error parsing JSON: $_");
    };
}

=head2 error

Log an error and die.

=cut

sub error {
    my ($self, $message) = @_;

    $self->logger->error($message);
    die $message;
}

1;
