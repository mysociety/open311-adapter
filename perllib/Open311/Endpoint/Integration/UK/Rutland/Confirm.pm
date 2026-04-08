package Open311::Endpoint::Integration::UK::Rutland::Confirm;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

use Open311::Endpoint::Service::UKCouncil::Confirm;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'rutland_confirm';
    $args{publish_service_update_text} = 1;
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

around _parse_enquiry_status_log => sub {
    my ($orig, $self) = (shift, shift);
    my $status_log = $_[0];

    unless ($status_log->{EnquiryStatusCode} eq 'FMS') {
        $status_log->{StatusLogNotes} = '';
    };

    $self->$orig(@_);
};

1;
