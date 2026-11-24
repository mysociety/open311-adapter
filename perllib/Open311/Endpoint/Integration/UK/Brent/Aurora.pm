=head1 NAME

Open311::Endpoint::Integration::UK::Brent::Aurora - Brent-specific parts of the Aurora integration

=cut

package Open311::Endpoint::Integration::UK::Brent::Aurora;

use Moo;
extends 'Open311::Endpoint::Integration::Aurora';

has jurisdiction_id => (
    is => 'ro',
    default => 'brent_aurora',
);

=head2 build_case_payload

The asset a report is made against (C<UnitID>) is from a layer hosted by
FMS, not an Aurora asset, so it is not sent as the C<internalAssetId>. It is
included in the description instead.

Additionally a user defined field 'FMSL' is set to the report URL to
display a clickable link in the Aurora UI.

=cut

around build_case_payload => sub {
    my ($orig, $self, $args, $category) = @_;

    my $payload = $self->$orig($args, $category);
    delete $payload->{internalAssetId};

    my $attributes = $args->{attributes};
    $payload->{userDefinedFields} = [
        {
           userDefinedFieldName => 'FMSL',
           userDefinedFieldValue => $attributes->{report_url},
        }
    ];

    return $payload;
};

=head2 build_case_description

The description is the report's description, followed by the ID of the
selected asset, the location query and the report URL, where present.
The report's title is not included; it is sent as the C<locationText>.

=cut

sub build_case_description {
    my ($self, $args) = @_;

    my $attributes = $args->{attributes};
    my @parts = ($attributes->{description});
    push @parts, "Asset ID: $attributes->{UnitID}" if $attributes->{UnitID};
    push @parts, "Location query entered: $args->{address_string}" if $args->{address_string};
    push @parts, "View report on FixMyStreet: $attributes->{report_url}" if $attributes->{report_url};

    return join "\n\n", @parts;
}

1;
