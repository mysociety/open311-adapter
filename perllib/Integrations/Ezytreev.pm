package Integrations::Ezytreev;

use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::MaybeXS;
use MIME::Base64 qw(encode_base64);

use Moo;
with 'Role::Config';
with 'Role::Logger';

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);

# Despite the name, this is also used for creating enquiries.
sub update_enquiry {
    my ($self, $body) = @_;

    my $url = $self->config->{endpoint_url} . "UpdateEnquiry";
    my $request = POST $url,
        'Content-Type' => 'application/json',
        Accept => 'application/json',
        Content => encode_json($body);
    $request->authorization_basic(
        $self->config->{username}, $self->config->{password});

    return $self->ua->request($request);
}

sub upload_enquiry_document {
    my ($self, $args) = @_;

    my $photo = $self->ua->get($args->{media_url});
    die "Failed to retrieve photo from $args->{media_url}\n" unless $photo->is_success;

    my $body = {
        CRMXRef => $args->{crm_xref},
        FileName => $photo->filename,
        Description => "Photo from problem reporter.",
        FileBase64 => encode_base64($photo->content),
    };

    my $url = $self->config->{endpoint_url} . "UploadEnquiryDocumentBase64";
    my $request = POST $url,
        'Content-Type' => 'application/json',
        Accept => 'application/json',
        Content => encode_json($body);
    $request->authorization_basic(
        $self->config->{username}, $self->config->{password});

    return $self->ua->request($request);
}

sub get_enquiry_changes {
    my $self = shift;
    my $url = $self->config->{endpoint_url} . "GetEnquiryChanges";
    my $request = GET $url, Accept => 'application/json';
    $request->authorization_basic(
        $self->config->{username}, $self->config->{password});

    return $self->ua->request($request);
}

1;
