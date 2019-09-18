# open311-adapter

An Open311 adapter to receive Open311 reports from FixMyStreet and send them on
to non-Open311 services.

## Install

Get the code using git and then run `script/bootstrap`.

    git clone https://github.com/mysociety/open311-adapter.git
    cd open311-adapter
    ./script/bootstrap

This will install the Perl modules necessary for running this application. You
should now be able to run the tests, and they should all pass.

    ./script/test

## Usage

Once you've installed the application you should be able to start the server.

    ./script/server

By default this will start listening on port 5000, so you can access it at
<http://localhost:5000/>. If you'd like to use another port then set the
`OPEN_ADAPTER_PORT` environment variable to the number of the port you'd like
to use.

    OPEN_ADAPTER_PORT=8080 ./script/server
