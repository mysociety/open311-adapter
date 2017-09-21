package Open311::Endpoint::Integration::Confirm;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::UKCouncil;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update;

use SOAP::Lite +trace => [ qw/method debug/ ];


=head2 service_whitelist

Controls the mapping of Confirm service/subject codes to Open311 services.
Subclasses must override this or no Open311 services will be published!

Returns a hashref which groups services together and optionally provides
an overridden name for each service.

For example, the following hashref will publish 5 Open311 services:

{
    'Roads' => {
        RO_PH => 1,
        RO_GB => 1,
        RO_LP => "Faded Markings",
    },
    'Lighting' => {
        LG_SL => 1,
        LG_BL => 1,
    }
}

3 services will be published with their group set to 'Roads', and two in
the 'Lighting' group. RO_PH, RO_GB, LG_SL, and LG_BL will take the subject
name from Confirm as their Open311 service name. RO_LP shows how the Confirm
default can be overridden, and this service will be published as 'Faded
Markings'.

I opted for a whitelist instead of a blacklist because Councils tend to have
hundreds of available service/subject codes in their Confirm instances but
typically only want to publish a small number (to begin with) on FixMyStreet.

=cut

has service_whitelist => (
    is => 'ro',
    default => sub { die "Attribute Confirm::service_whitelist not overridden"; }
);


=head2 ignored_attributes

Some Confirm attributes should never be published in the Open311 service
metadata.

This attribute should be an arrayref of Confirm attribute codes to ignore.

=cut

has ignored_attributes => (
    is => 'ro',
    default => sub { [] }
);

=head2 ignored_attribute_options

Some options Confirm attributes should never be published in the Open311 service
metadata.

This attribute should be an arrayref of Confirm attribute option codes to ignore.

=cut

has ignored_attribute_options => (
    is => 'ro',
    default => sub { [] }
);


=head2 attribute_descriptions

Some Confirm attribute names can be quite opaque and not very helpful for the
end user. This mapping allows individual attribute names to be overridden.

=cut

has attribute_descriptions => (
    is => 'ro',
    default => sub { {} }
);


sub get_integration {
    my $self = shift;
    return $self->integration_class->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = $self->get_integration;

    if ($args->{address_string}) {
        $args->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }

    my $new_id = $integ->NewEnquiry($service, $args);

    die "Couldn't create Enquiry in Confirm" unless defined $new_id;

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub services {
    my $self = shift;

    my $integ = $self->get_integration;

    my $response = $integ->GetEnquiryLookups();
    my $confirm_services = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{TypeOfService};

    my $available_attributes = $self->_parse_attributes($response);

    my %ignored_attribs = map { $_ => 1 } @{$self->ignored_attributes};

    my %services = ();
    for my $service (@$confirm_services) {
        my $servicename = $service->{ServiceName};
        my $servicecode = $service->{ServiceCode};

        my $subjects = $service->{EnquirySubject};
        $subjects = [ $subjects ] if (ref($subjects) eq 'HASH');

        for my $subject (@$subjects) {
            my $code = $servicecode . "_" . $subject->{SubjectCode};

            my $subjectattributes = $subject->{SubjectAttribute};
            $subjectattributes = [ $subjectattributes ] if (ref($subjectattributes) eq 'HASH');

            my @attribs = map {
                $available_attributes->{$_->{EnqAttribTypeCode}}
            } grep {
                !$ignored_attribs{$_->{EnqAttribTypeCode}}
            } @$subjectattributes;

            $services{$code} = {
                service => $service,
                subject => $subject,
                attribs => \@attribs,
            };
        }
    }

    my @services = ();
    for my $group (keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $code (keys %{ $whitelist }) {
            my $subject = $services{$code}->{subject};
            if (!$subject) {
                printf("$code doesn't exist in Confirm.\n");
                next;
            }
            my $name = $whitelist->{$code} eq 1 ? $subject->{SubjectName} :  $whitelist->{$code};
            my %service = (
                service_name => $name,
                service_code => $code,
                description => $name,
                group => $group,
            );
            my $o311_service = Open311::Endpoint::Service::UKCouncil->new(%service);
            for (@{$services{$code}->{attribs}}) {
                push @{$o311_service->attributes}, $_;
            }
            push @services, $o311_service;
        }
    }
    return @services;
}

sub get_service_request {
    my ($self, $id) = @_;

    my $response = $self->get_integration->GetEnquiry($id);

    return Open311::Endpoint::Service::Request->new();
}


sub _parse_attributes {
    my ($self, $response) = @_;

    my %attributes = ();

    my $attribute_types = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{EnquiryAttributeType};

    my %ignored_options = map { $_ => 1 } @{$self->ignored_attribute_options};

    for (@$attribute_types) {
        my $code = $_->{EnqAttribTypeCode};

        my $required = $_->{MandatoryFlag} eq 'true' ? 1 : 0;
        my $desc = $self->attribute_descriptions->{$code} || $_->{EnqAttribTypeName};
        my $enquiry_attributes = $_->{EnquiryAttributeValue};
        $enquiry_attributes = [ $enquiry_attributes ] if (ref($enquiry_attributes) eq 'HASH');
        my %values = map {
            if ($ignored_options{$_->{EnqAttribValueCode}}) {
                ()
            } else {
                $_->{EnqAttribValueCode} => $_->{EnqAttribValueName}
            }
        } @{ $enquiry_attributes };
        my $type = %values ? 'singlevaluelist' : 'string';


        # printf "\n\nXXXXXXXX $code\n\n\n" if $type eq 'singlevaluelist';

        $attributes{$code} = Open311::Endpoint::Service::Attribute->new(
            code => $code,
            description => $desc,
            datatype => $type,
            required => $required,
            values => \%values,
        );
    }

    return \%attributes;
}

1;
