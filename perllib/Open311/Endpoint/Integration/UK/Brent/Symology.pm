package Open311::Endpoint::Integration::UK::Brent::Symology;

use Moo;
extends 'Open311::Endpoint::Integration::Symology';

use Open311::Endpoint::Service::UKCouncil::Symology::Brent;

has jurisdiction_id => (
    is => 'ro',
    default => 'brent_symology',
);

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Symology::Brent'
);

sub process_service_request_args {
    my $self = shift;

    my $location = (delete $_[0]->{attributes}->{title}) || '';
    my @args = $self->SUPER::process_service_request_args(@_);
    my $response = $args[0];
    $response->{Location} = $location;

    push @{ $args[2] }, [ FieldLine => 3, ValueType => 8,  DataValue => $_[0]->{attributes}->{report_url} ];
    # Add the photo URLs to the request
    my $field_line_value = 4;

    foreach my $photo_url ( @{ $_[0]->{media_url} } ) {
        push @{ $args[2] }, [ FieldLine => $field_line_value, ValueType => 7, DataValue => $photo_url ];

        # Only send the first three photos
        last if $field_line_value == 6;

        $field_line_value++;
    };
    return @args;
}

# Fetching updates will not currently work due to missing functions/setup

1;
