=head1 NAME

Integrations::Surrey::Boomi - Interface to the Surrey Boomi REST API

=cut

package Integrations::Surrey::Boomi;

use strict;
use warnings;

use Moo;
use URI;
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
        $ua->ssl_opts(SSL_cipher_list => 'DEFAULT:!DH'); # Disable DH ciphers, server's key is too small apparently
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
    if (my $errors = $resp->{errors}) {
        $self->logger->error("[Boomi] Error upserting ticket:");
        $self->logger->error($_->{error} . ": " . $_->{details}) for @$errors;
        die;
    }
    if (my $warnings = $resp->{warnings}) {
        $self->logger->warn("[Boomi] Warnings when upserting ticket: ");
        $self->logger->warn($_->{warning} . ": " . $_->{details}) for @$warnings;
    }
    if (my $ticket = $resp->{ticket}) {
        return $ticket->{system} . "_" . $ticket->{id};
    }
    $self->error("Couldn't determine ID from response: " . encode_json($resp));
}

=head2 getHighwaysTicketUpdates

Create or update a ticket in the Surrey Boomi system.

Returns the ID of the created or updated ticket.

=cut

sub getHighwaysTicketUpdates {
    my ($self, $integration_id, $start, $end) = @_;

    my $resp = $self->get('getHighwaysTicketUpdates', {
        from => format_datetime($start),
        to => format_datetime($end),
        integration_id => $integration_id,
    });

    if (my $errors = $resp->{errors}) {
        $self->logger->error("[Boomi] Error fetching updates:");
        $self->logger->error($_->{error} . ": " . $_->{details}) for @$errors;
        die;
    }
    if (my $warnings = $resp->{warnings}) {
        $self->logger->warn("[Boomi] Warnings when fetching updates:");
        $self->logger->warn($_->{warning} . ": " . $_->{details}) for @$warnings;
    }

    return $resp->{results} || [];
}

=head2 getNewHighwaysTickets

Get new tickets from the Surrey Boomi system.

=cut

sub getNewHighwaysTickets {
    my ($self, $integration_id, $start, $end) = @_;

    my $resp = $self->get('getNewHighwaysTickets', {
        integration_id => $integration_id,
        from => format_datetime($start),
        to => format_datetime($end),
    });

    if (my $errors = $resp->{errors}) {
        $self->logger->error("[Boomi] Error fetching new tickets:");
        $self->logger->error($_->{error} . ": " . $_->{details}) for @$errors;
        die;
    }
    if (my $warnings = $resp->{warnings}) {
        $self->logger->warn("[Boomi] Warnings when fetching new tickets:");
        $self->logger->warn($_->{warning} . ": " . $_->{details}) for @$warnings;
    }

    return $resp->{results} || [];
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
    $self->logger->debug("[Boomi] Request URL for POST: $url");
    $self->logger->debug("[Boomi] Request content: $content");

    my $response = $self->ua->post(
        $url,
        Content => $content,
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

=head2 get

Make a GET request to the Boomi API with the given path and query params.

Returns the decoded JSON from the response, if possible, otherwise logs an
error and dies.

=cut

sub get {
    my ($self, $path, $params) = @_;

    my $uri = URI->new( $self->config->{api_url} . $path );
    $uri->query_form(%$params);

    my $request = HTTP::Request->new("GET", $uri);
    $self->logger->debug("[Boomi] Request: " . $request->as_string);

    my $response = $self->ua->request($request);

    $self->logger->debug("[Boomi] Response status: " . $response->status_line);
    $self->logger->debug("[Boomi] Response content: " . $response->decoded_content);

    if (!$response->is_success) {
        $self->error("[Boomi] GET request failed: " . $response->status_line);
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


=head2 format_datetime

Format a DateTime object as a string in the format expected by the Boomi API.
(Adapted from DateTime::Format::W3CDTF to always include milliseconds.)

=cut
sub format_datetime {
    my $dt = shift;

    my $cldr = 'yyyy-MM-ddTHH:mm:ss.SSS';

    my $tz;
    if ( $dt->time_zone->is_utc ) {
        $tz = 'Z';
    }
    else {
        $tz = q{};
        $cldr .= 'ZZZZZ';
    }

    return $dt->format_cldr($cldr) . $tz;
}

1;
