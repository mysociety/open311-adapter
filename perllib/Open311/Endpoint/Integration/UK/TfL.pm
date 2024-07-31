=head1 NAME

Open311::Endpoint::Integration::UK::TfL - Tfl Atlas backend.

=head1 SUMMARY

This is a TfL-specific Passthrough intergration for their Atlas backend.
It is a standard Open311 server apart from it passes a bearer token
fetched from their OAuth2 API and a 'Ocp-Apim-Subscription-Key' header.

=cut

package Open311::Endpoint::Integration::UK::TfL;

use HTTP::Request::Common;
use JSON::MaybeXS;
use LWP::UserAgent;
use Moo;
extends 'Open311::Endpoint::Integration::Passthrough';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'tfl';
    return $class->$orig(%args);
};

has oauth2_url => ( is => 'ro' );
has oauth2_client_id => ( is => 'ro' );
has oauth2_client_secret => ( is => 'ro' );
has oauth2_tenant_id => ( is => 'ro' );
has ocp_apim_subscription_key => ( is => 'ro' );

has oauth2_token => (
    is => 'lazy',
    default => sub {
        my $self = shift;

        my $token = $self->memcache->get('tfl_atlas_oauth2_token');
        unless ($token) {
            my $url = $self->oauth2_url . $self->oauth2_tenant_id . "/oauth2/token";
            my $req = POST $url, [
                grant_type => "client_credentials",
                client_id => $self->oauth2_client_id,
                client_secret => $self->oauth2_client_secret,
            ];
            my $response = $self->ua->request($req);
            unless ($response->is_success) {
                $self->logger->warn("Getting OAuth2 token failed: $url");
                return;
            }
            my $content = decode_json($response->content);
            $token = $content->{access_token};
            $self->memcache->set('tfl_atlas_oauth2_token', $token, time() + $content->{expires_in} - 10);
        }
        return $token;
    },
);

sub _headers {
    my $self = shift;
    return {
        'Ocp-Apim-Subscription-Key' => $self->ocp_apim_subscription_key,
        'Authorization' => 'Bearer ' .  $self->oauth2_token,
    };
}

1;
