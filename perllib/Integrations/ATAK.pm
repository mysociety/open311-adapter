=head1 NAME

Integrations::ATAK - Interface to the Continental Landscapes ATAK system

=cut

package Integrations::ATAK;

use strict;
use warnings;

use Moo;
use LWP::UserAgent;
use JSON::MaybeXS;
use Try::Tiny;

with 'Role::Logger';
with 'Role::Config';

=head1 ATTRIBUTES

=head2 token

Login token used for authenticating with the ATAK API.

=cut

has token => (
    is  => 'lazy',
    default => sub {
        my ($self) = @_;

        my $response = $self->ua->post(
            $self->config->{api_url} . '/login',
            Content_Type => 'form-data',
            Content      => [ username => $self->config->{username}, password => $self->config->{password} ]
        );

        if (!$response->is_success) {
            $self->error("Authentication failed: " . $response->status_line);
        }

        my $content = $response->decoded_content;
        if (!$content) {
            $self->error("Authentication failed: No content received.");
        }

        my $json_content = decode_json($content);
        if (!$json_content || !$json_content->{token}) {
            $self->error("Authentication failed: No token received.");
        }

        return $json_content->{token};
    },
);

=head2 ua

The LWP::UserAgent object used to make requests to the ATAK API.

=cut

has ua => (
    is  => 'rw',
    default => sub { LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter") },
);

=head1 METHODS

=head2 create_issue

Create an issue in the Continental Landscapes ATAK system.

=cut

sub create_issue {
    my ($self, $issue_data) = @_;

    my $request_data = { tasks => [ $issue_data] };
    my $response = $self->post('/enq', $request_data);

    my $issue_id = $response->{'Processed task 1'};
    if (!$issue_id) {
        $self->error("No issue ID received.");
    }

    return $issue_id;
}

=head2 post

Make a POST request to the ATAK API with the given path and data.

Uses the token for authentication.

Returns the JSON response.

=cut

sub post {
    my ($self, $path, $data) = @_;

    my $url = $self->config->{api_url} . $path;
    $self->logger->debug("[ATAK] Request URL: $url");

    my $response = $self->ua->post(
        $url,
        'Authorization' => $self->token,
        'Content-Type'  => 'application/json',
        Content         => encode_json($data)
    );

    $self->logger->debug("[ATAK] Response status: " . $response->status_line);
    $self->logger->debug("[ATAK] Response content: " . $response->decoded_content);

    if (!$response->is_success) {
        $self->error("ATAK POST request failed: " . $response->status_line);
    }

    try {
        my $content = $response->decoded_content;
        return decode_json($content);
    } catch {
        $self->error("Error parsing JSON: $_");
    };
}

=head2 error

Log an error and die.

=cut

sub error {
    my ($self, $message) = @_;

    $self->logger->error("[ATAK] $message");
    die $message;
}

1;
