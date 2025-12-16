=head1 NAME

Integrations::Aurora

=head1 DESCRIPTION

This module provides an interface to the Aurora Cases API

https://cases.aurora.symology.net/swagger/index.html

=cut

package Integrations::Aurora;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::Common;
use JSON::MaybeXS;
use LWP::UserAgent;
use Moo;
use MIME::Base64 qw(decode_base64);
use URI::Escape;

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

has oauth_username => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth}->{username} }
);

has oauth_password => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth}->{password} }
);

has oauth_client_id => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth}->{client_id} }
);

has oauth_client_secret => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth}->{client_secret} }
);

has oauth_access_token_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{oauth}->{access_token_url} }
);

has cases_api_base_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{cases_api_base_url} }
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
            my $response = $self->ua->request(POST $self->oauth_access_token_url,
                 [
                    grant_type => 'password',
                    scope => "Symology.Aurora.Customer.Api.User",
                    username => $self->oauth_username,
                    password => $self->oauth_password,
                    client_id => $self->oauth_client_id,
                    client_secret => $self->oauth_client_secret,
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

=head1 METHODS

=cut

=head2 get_contact_id_for_email_address

Returns, the ID of the first contact found with a matching email,
or undef if no match is found.
Assumes any match will always be in the first page of results.

=cut

sub get_contact_id_for_email_address {
    my ($self, $email_address) = @_;
    my $token = $self->access_token or die "Failed to get access token.";
    my $request = GET $self->cases_api_base_url .
        "Cases/Contact?emailAddress=" . uri_escape($email_address),
        Authorization => "Bearer $token",
    ;
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to query contacts", $request, $response);
    }
    my $content = decode_json($response->content);
    foreach (@{$content->{contacts}}) {
        if ($_->{emailAddress} eq $email_address) {
            return $_->{id};
        }
    };
    return undef;
}

=head2 create_contact_and_get_id

Creates a contact with the given email, first name, last name and
number, and returns its ID.

=cut

sub create_contact_and_get_id {
    my ($self, $email_address, $first_name, $last_name, $number) = @_;
    my $token = $self->access_token or die "Failed to get access token.";
    my $payload = {
        firstName => $first_name,
        lastName => $last_name,
        emailAddress => $email_address,
    };
    if ($number) {
        $number =~ s/\D//g;  # remove non-digits
        $number = "0$number" if $number =~ /^44/;  # replace country code with 0
        if ($number =~ /^07/) {
            $payload->{mobilePhone} = $number;
        } else {
            $payload->{homePhone} = $number;
        }
    }
    my $request = HTTP::Request->new(
        'POST',
        $self->cases_api_base_url . "Cases/Contact/CreateContact",
        [
            Authorization => "Bearer $token",
            "Content-Type" => "application/json",
        ],
        encode_json($payload)
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to create contact", $request, $response);
    }
    my $content = decode_json($response->content);
    return $content->{contactId};
}

=head2 upload_attachment_and_get_id

Takes the path to a local file, uploads it as an attachment and returns the ID.

=cut

sub upload_attachment_and_get_id {
    my ($self, $filename) = @_;
    die "File not found: $filename" unless -f $filename;
    die "File not readable: $filename" unless -r $filename;

    my $token = $self->access_token or die "Failed to get access token.";
    my $request = HTTP::Request::Common::POST(
        $self->cases_api_base_url . "Attachments",
        Authorization => "Bearer $token",
        Content_Type => "form-data",
        Content => [
            file => [ $filename ],
        ],
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to upload attachment", $request, $response);
    }
    return $response->content;
}

=head2 create_case_and_get_number

Creates a case using the given payload and returns the case number.

=cut

sub create_case_and_get_number {
    my ($self, $payload) = @_;

    my $token = $self->access_token or die "Failed to get access token.";
    my $request = HTTP::Request->new(
        'POST',
        $self->cases_api_base_url . "Cases/Case/CreateCase",
        [
            Authorization => "Bearer $token",
            "Content-Type" => "application/json",
        ],
        encode_json($payload)
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to create case ", $request, $response);
    }
    my $content = decode_json($response->content);
    return $content->{caseNumber};
}

=head2 add_note_to_case

Adds a note to the given case.

=cut

sub add_note_to_case {
    my ($self, $case_number, $payload) = @_;

    my $token = $self->access_token or die "Failed to get access token.";
    my $request = HTTP::Request->new(
        'POST',
        $self->cases_api_base_url . "Cases/Case/AddNote?caseNumber=" . $case_number,
        [
            Authorization => "Bearer $token",
            "Content-Type" => "application/json",
        ],
        encode_json($payload)
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to add note to case $case_number", $request, $response);
    }
    return;
}

sub _fail {
    my ($self, $message, $request, $response) = @_;
    my $request_string = $request->as_string;
    $request_string =~ s/(Authorization: ).+/$1\[REDACTED\]/;
    $self->logger->error(sprintf(
        "%s\n\nRequested:\n\n%s\n\nGot:\n\n%s",
        $message, $request_string, $response->as_string
    ));
    die $message;
}

1;
