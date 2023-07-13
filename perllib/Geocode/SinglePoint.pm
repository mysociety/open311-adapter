package Geocode::SinglePoint;

use v5.14;
use warnings;

use Data::Dumper;
use LWP::UserAgent;
use Moo;
use XML::Simple qw(:strict);

with 'Role::Config';
with 'Role::Logger';

has base_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{singlepoint_api_base_url}  }
);

has api_key => (
    is => 'lazy',
    default => sub { $_[0]->config->{singlepoint_api_key}  }
);

has ua => (
    is => 'lazy',
    default => sub { LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter") }
);

sub _fail {
    my ($self, $message, $url, $response) = @_;
    my $log = sprintf(
        "%s
        Requested: %s
        Got: %s",
        $message, $url, $response->content
    );
    $self->logger->error($log);
    die $message;
}

sub _get_field_value_for_tag {
    my ($self, $dom, $tag) = @_;
    return $self->xml_path_context->findvalue('./x:FieldItems/x:FieldInfo/x:Value[../x:Tag="'. $tag . '"]', $dom);
}

sub get_nearest_addresses {
    my ($self, $easting, $northing, $radius_meters, $address_field_tags) = @_;
    my $url = sprintf(
        "%sSpatialRadialSearchByEastingNorthing?apiKey=%s&adapterName=LLPG&easting=%s&northing=%s&unit=Meter&distance=%s",
        $self->base_url,
        $self->api_key,
        $easting,
        $northing,
        $radius_meters,
    );
    my $response = $self->ua->get($url);
    if (!$response->is_success) {
        $self->_fail("Request failed.", $url, $response);
    }
    my $x = XML::Simple->new(ForceArray => ["SearchResultItem", "FieldInfo"], NoAttr => 1, SuppressEmpty => "", KeyAttr => ["Tag"]);
    my $xml = $x->XMLin($response->content);
    my $results = $xml->{Results}{Items}{SearchResultItem};

    my @addresses;
    # Results are already ordered nearest-first.
    foreach my $result (@$results) {

        my %address;
        foreach my $address_field_tag (@$address_field_tags) {
            my $field = $result->{FieldItems}{FieldInfo}{$address_field_tag};
            $address{$address_field_tag} = $field->{Value} if $field;
        }
        push @addresses, \%address if %address;
    }

    return \@addresses;
}

1;
