package Open311::Endpoint::Integration::UK::Hackney;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hackney_highways_alloy_v2';
    return $class->$orig(%args);
};

# basic services creating without setting up attributes from Alloy
sub services {
    my $self = shift;

    my @services = ();
    my %categories = ();
    for my $group (sort keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $subcategory (sort keys %{ $whitelist }) {
            $categories{$subcategory} ||= [];
            push @{ $categories{$subcategory} }, $group;
        }
    }

    for my $category (sort keys %categories) {
        my $name = $category;
        my $code = $name;
        my %service = (
            service_name => $name,
            description => $name,
            service_code => $code,
            groups => $categories{$category},
        );
        my $o311_service = $self->service_class->new(%service);

        push @services, $o311_service;
    }

    return @services;
}

1;
