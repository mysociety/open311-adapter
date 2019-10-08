# Overview

Reports are sent to Alloy as Requests for Service Enquiries.

Updates are fetched by checking for updated Requests for Service
Enquiries and also for updated Defects. A Defect is linked to an Enquiry
either as a parent or by including the FixMyStreet id number in an
attribute with a code ending `FIXMYSTREET_ID`. In the case of the former
we get the FixMyStreet id for the update by looking up the parent
Enquiry and fetching the id from that.

## Enquiry state

This is determined from two fields:

* Enquiry status
* Reason for closure

If the state of the enquiry is not `Completed` then we directly map the
state to a FixMyStreet state.

If the enquiry is `Completed` then we use the `Reason for Closure` to
map to a FixMyStreet status. If there is no `Reason for Closure` then
the FixMyStreet status is `closed`.

The `Reason for Closure` is also set to the external_status of the
update. This is only done if the state is `Completed` otherwise we can
get spurious updates caused by an Alloy user saving the
`Reason for Closure` first and then saving the `Completed` status. In this case
FixMyStreet gets two updates which it acts upon as the first contains
a change to the `external_status` and the second contains a change to
the state.

## Defect state

The Defect status is directly mapped to a FixMyStreet state.

One small tweak is that if the Defect state is mapped to
`action_scheduled` we include the `external_status`. Again this is to
prevent spurious updates caused by apparent changes in
`external_status`.

This happens because the Enquiry will end up in an `action_scheduled`
state, which is set using the `Reason for Closure`, hence will set an
`external_status` on the relevant update. At this point a Defect will
be created from the Enquiry, which will shortly be set to an
`action_scheduled` status, by default generating an update without an
`external_status`.

We have to have an `action_scheduled` state for Defects to handle those
Defects created by inspectors without an associated Enquiry.

## Update fetching

Enquiries in Alloy are versioned and a new version is created every
time a property is changed. To get the updates to an Enquiry we loop
over the list of updated items and fetch all previous versions. We
then discard all versions created outside the start/end times of
the update call. We then create an update for each remaining
version and allow FixMyStreet to handle discarding duplicates and
empty changes.
