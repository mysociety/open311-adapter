package Integrations::Rest;

use Moo;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON::MaybeXS qw(encode_json decode_json);

with 'Role::Config';
with 'Role::Logger';

=head2 caller

This is a generic JSON integrater and needs to register which integration it is being called
for to identify in error logs

=cut

has caller => (
    is => 'ro',
    required => 1,
);

=head2 allow_nonref

Set whether json decoding allows non json data (ie a string)
to be parsed - defaults to 0

=cut

has allow_nonref => (
    is => 'ro',
    default => 0
);

=head2 api_call

api calls are either GET or POSTING JSON data.

Expects {
    call => ** string uri **,
    headers => ** hashref of headers **
    body => ** hashref of data to be JSON-encoded, or **
    form => ** hashref or arrayref of form data **
}

JSON is expected in a successful response, but allow_nonref can be set in initialisation.

=cut

sub api_call {
    my ($self, %args) = @_;

    my $call = $args{call};
    my $body = $args{body};
    my $form = $args{form};
    my $headers = $args{headers};

    $self->logger->debug($call);

    my $ua = LWP::UserAgent->new(
        agent => "FixMyStreet/open311-adapter",
        timeout => 5*60,
    );

    my $method = $args{method};
    $method = ($body || $form) ? 'POST' : 'GET' unless $method;
    $method = HTTP::Request::Common->can($method);

    my $uri = URI->new( $self->config->{api_url} . $call );
    $uri->query_form(%{ $args{params} });

    if ($body) {
        $headers->{Content_Type} = 'application/json; charset=UTF-8';
        $body = encode_json($body);
        $headers->{Content} = $body;
        $self->logger->debug($body);
    }
    if ($form) {
        my @data = ref($form) eq "HASH" ? %$form : @$form;
        while (my ($k,$v) = splice(@data, 0, 2)) {
            if (ref($v)) {
                $headers->{Content_Type} = 'form-data';
            }
        }
    }

    my $request = $method->($uri, $form ? ($form) : (), %$headers);
    my $response = $ua->request($request);
    if ($response->is_success) {
        $self->logger->debug($response->content);
        return decode_json($response->content, $self->allow_nonref);
    } else {
        $self->logger->error($call);
        $self->logger->error(encode_json($body)) if $body and (ref $body eq 'HASH' || ref $body eq 'ARRAY');
        $self->logger->error($response->content);
        try {
            my $json_response = decode_json($response->content, $self->allow_nonref);
            my $code = $json_response->{code} || "";
            my $msg = $json_response->{message} || "";
            die $self->caller . " call failed: [$code] $msg";
        } catch {
            die $response->content;
        };
    }
}

1;
