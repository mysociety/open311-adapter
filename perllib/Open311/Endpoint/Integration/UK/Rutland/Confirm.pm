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

=head2 photo_filter

Rutland want us to return photos with specific classification
tag.

=cut

around photo_filter => sub {
    my ($orig, $self, $doc) = @_;
    return 0 unless $doc->{ClassificationCode} && $doc->{ClassificationCode} =~ /^DT[12]0$/;
    return $self->$orig($doc);
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
