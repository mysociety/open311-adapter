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
        my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
        my $uri = URI->new($_[0]->config->{endpoint_url});
        my $netloc = $uri->host . ":" . $uri->port;
        $ua->credentials($netloc, "", $_[0]->config->{username}, $_[0]->config->{password});
        return $ua;
    },
);

# Despite the name, this is also used for creating enquiries.
sub update_enquiry {
    my ($self, $body) = @_;

    my $url = $self->config->{endpoint_url} . "UpdateEnquiry";
    my $request = POST $url,
        Content_Type => 'application/json',
        Accept => 'application/json',
        Content => encode_json($body);

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
        Content_Type => 'application/json',
        Accept => 'application/json',
        Content => encode_json($body);

    return $self->ua->request($request);
}

sub get_enquiry_changes {
    my ($self, $start, $end) = @_;

    # The endpoint takes dates only.
    # Results are always from the start of the start date to the end of the end date.
    my $start_date = $start->ymd;
    my $end_date = $end->ymd;

    my $url = $self->config->{endpoint_url} . "Enquiries/Changes/$start_date/$end_date";
    my $request = GET $url, Accept => 'application/json';
    return $self->ua->request($request);
}

1;
