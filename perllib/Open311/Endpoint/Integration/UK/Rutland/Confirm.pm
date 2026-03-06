package Open311::Endpoint::Integration::UK::Rutland::Confirm;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

use Open311::Endpoint::Service::UKCouncil::Confirm;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'rutland_confirm';
    return $class->$orig(%args);
};

=head2 filter_photos_graphql

Rutland want us to return photos with specific classification
tag.

=cut

around filter_photos_graphql => sub {
    my ($orig, $self, @photos) = @_;
    my @filtered = $self->$orig(@photos);
    return grep { $_->{ClassificationCode} && $_->{ClassificationCode} eq 'DT20' } @filtered;
};


1;
