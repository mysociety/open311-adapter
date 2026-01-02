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
use XML::Simple;
use JSON::MaybeXS;
use LWP::UserAgent;
use Moo;
use MIME::Base64 qw(decode_base64);
use URI::Escape;
use Try::Tiny;

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

has cases_api_base_url => (
    is => 'lazy',
    default => sub {
        my $url = $_[0]->config->{cases_api_base_url};
        $url .= '/' unless $url =~ m{/$};
        return $url;
    }
);

=head2 updates_azure_container_base_url

The base URL of the Azure API hosting the Aurora 'return path updates' container.

=cut

has updates_azure_container_base_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{updates_azure_container_base_url} }
);

=head2 updates_azure_container_url_arguments

Arguments to use in a query string when making requests using c<updates_azure_container_base_url>.
Can be used for things like setting the SAS token for auth.

=cut

has updates_azure_container_url_arguments => (
    is => 'lazy',
    default => sub { $_[0]->config->{updates_azure_container_url_arguments} }
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

=head1 METHODS

=cut

=head2 _normalise_phone_number

Remove any non-digits and replace leading '44' country code with '0'.

=cut

sub _normalise_phone_number {
    my ($self, $number) = @_;
    $number =~ s/\D//g;  # remove non-digits
    $number =~ s/^44/0/;  # replace country code with 0
    return $number;
}

=head2 _is_phone_number_mobile

Returns true if the number appears to be a mobile number.

=cut

sub _is_phone_number_mobile {
    my ($self, $number) = @_;
    return $number =~ /^07/;
}

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

=head2 get_contact_id_for_phone_number

Returns, the ID of the first contact found with a matching phone number,
or undef if no match is found.
Assumes any match will always be in the first page of results.

=cut

sub get_contact_id_for_phone_number {
    my ($self, $number) = @_;
    my $token = $self->access_token or die "Failed to get access token.";

    my $normalised_number = $self->_normalise_phone_number($number);
    my $aurora_field;
    if ($self->_is_phone_number_mobile($normalised_number)) {
        $aurora_field = "mobilePhone";
    } else {
        $aurora_field = "homePhone";
    }

    my $query_string = "?$aurora_field=$normalised_number";
    my $request = GET $self->cases_api_base_url .
        "Cases/Contact" . $query_string,
        Authorization => "Bearer $token",
    ;
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to query contacts", $request, $response);
    }
    my $content = decode_json($response->content);
    foreach (@{$content->{contacts}}) {
        my $normalised_contact_number = $self->_normalise_phone_number($_->{$aurora_field});
        if ($normalised_contact_number eq $normalised_number) {
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
        my $normalised_number = $self->_normalise_phone_number($number);
        if ($self->_is_phone_number_mobile($normalised_number)) {
            $payload->{mobilePhone} = $normalised_number;
        } else {
            $payload->{homePhone} = $normalised_number;
        }
    }
    my $request = POST(
        $self->cases_api_base_url . "Cases/Contact/CreateContact",
        Authorization => "Bearer $token",
        "Content-Type" => "application/json",
        Content => encode_json($payload),
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to create contact", $request, $response);
    }
    my $content = decode_json($response->content);
    return $content->{contactId};
}

sub _upload_attachment_and_get_id {
    my ($self, $content) = @_;
    my $token = $self->access_token or die "Failed to get access token.";
    my $request = POST(
        $self->cases_api_base_url . "Attachments",
        Authorization => "Bearer $token",
        Content_Type => "form-data",
        Content => $content,
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to upload attachment", $request, $response);
    }

    my $attachment_id = $response->content;
    $attachment_id =~ s/^"(.*)"$/$1/;
    return $attachment_id;
}

=head2 upload_attachment_from_file_and_get_id

Takes the path to a local file, uploads it as an attachment and returns the ID.

=cut

sub upload_attachment_from_file_and_get_id {
    my ($self, $filename) = @_;
    die "File not found: $filename" unless -f $filename;
    die "File not readable: $filename" unless -r $filename;
    return $self->_upload_attachment_and_get_id([
        file => [ $filename ],
    ]);
}

=head2 upload_attachment_response_and_get_id

Takes a HTTP::Response object containing media, uploads it as an attachment and returns the ID.

=cut

sub upload_attachment_from_response_and_get_id {
    my ($self, $response) = @_;
    return $self->_upload_attachment_and_get_id([
        file => [
            undef,  # From memory, not a local file.
            $response->filename,
            Content_Type => $response->header('Content_Type') || 'application/octet-stream',
            Content => $response->content,
        ],
    ]);
}

=head2 create_case_and_get_number

Creates a case using the given payload and returns the case number.

=cut

sub create_case_and_get_number {
    my ($self, $payload) = @_;

    my $token = $self->access_token or die "Failed to get access token.";
    my $request = POST(
        $self->cases_api_base_url . "Cases/Case/CreateCase",
        Authorization => "Bearer $token",
        "Content-Type" => "application/json",
        Content => encode_json($payload),
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
    my $request = POST(
        $self->cases_api_base_url . "Cases/Case/AddNote?caseNumber=" . $case_number,
        Authorization => "Bearer $token",
        "Content-Type" => "application/json",
        Content => encode_json($payload),
    );
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to add note to case $case_number", $request, $response);
    }
    return;
}

=head2 fetch_update_filenames

Queries for filenames in the 'return path updates' Azure storage container.

=cut

sub fetch_update_filenames {
    my ($self) = @_;

    my $request = GET($self->updates_azure_container_base_url . '?' . $self->updates_azure_container_url_arguments . '&comp=list&restype=container');
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to fetch update filenames", $request, $response);
    }
    try {
        my $data = XML::Simple->new->XMLin($response->content)->{Blobs}->{Blob};
        return @$data;
    } catch {
        $self->_fail("Failed to parsed fetched update filenames as XML", $request, $response);
    };
};

=head2 fetch_update_file

Return the parsed contents of the given file in the 'return path updates' Azure storage container.

=cut

sub fetch_update_file {
    my ($self, $filename) = @_;

    my $request = GET($self->updates_azure_container_base_url . "/$filename" . '?' . $self->updates_azure_container_url_arguments);
    my $response = $self->ua->request($request);
    if (!$response->is_success) {
        $self->_fail("Failed to fetch update file", $request, $response);
    }
    try {
        my $data = decode_json($response->content);
        return $data;
    } catch {
        $self->_fail("Failed to parse fetched update file as JSON", $request, $response);
    };
};

sub _fail {
    my ($self, $message, $request, $response) = @_;
    my $request_string = $request->as_string;
    $request_string =~ s/(Authorization: ).+/$1\[REDACTED\]/;  # Redact Aurora token.
    $request_string =~ s/(sig=)[^&\s]+/$1\[REDACTED\]/g;  # Redact Azure SAS token signature.
    $self->logger->error(sprintf(
        "%s\n\nRequested:\n\n%s\n\nGot:\n\n%s",
        $message, $request_string, $response->as_string
    ));
    die $message;
}

1;
