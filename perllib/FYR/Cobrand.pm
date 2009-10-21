#!/usr/bin/perl -w
#
# Cobrand.pm:
# Cobranding for WriteToThem.
#
# 
# Copyright (c) 2009 UK Citizens Online Democracy. All rights reserved.
# Email: louise@mysociety.org. WWW: http://www.mysociety.org
#
# $Id: Cobrand.pm,v 1.4 2009-10-21 16:03:36 louise Exp $

package FYR::Cobrand;
use strict;
use Carp;
use mySociety::Config;

=item cobrand_handle Q

Given a query that has the name of a site set, return a handle to the Util module for that
site, if one exists, or zero if not.

=cut
sub cobrand_handle {
    my $cobrand = shift;

    our %handles;

    # Once we have a handle defined, return it.
    return $handles{$cobrand} if defined $handles{$cobrand};

    my $cobrand_class = ucfirst($cobrand);
    my $class = "Cobrands::" . $cobrand_class . "::Util";
    eval "use $class";

    eval{ $handles{$cobrand} = $class->new };
    $handles{$cobrand} = 0 if $@;
    return $handles{$cobrand};
}

=item get_cobrand_conf COBRAND KEY

Get the value for KEY from the config file for COBRAND

=cut
sub get_cobrand_conf {
    my ($cobrand, $key) = @_;
    my $value; 
    if ($cobrand){
        (my $dir = __FILE__) =~ s{/[^/]*?$}{};
        my $cobrand_conf_file = "$dir/../../conf/cobrands/$cobrand/general";
        my $main_conf_file = "$dir/../../conf/general";
        if (-e $cobrand_conf_file){
            mySociety::Config::set_file($cobrand_conf_file);            
            $cobrand = uc($cobrand);
            $value = mySociety::Config::get($key . "_" . $cobrand, undef);
            mySociety::Config::set_file($main_conf_file);
        }
    }
    if (!defined($value)){
        $value = mySociety::Config::get($key);
    }
    return $value;
}

=item get_allowed_cobrands

Return an array reference of allowed cobrand subdomains

=cut
sub get_allowed_cobrands {
    my $allowed_cobrand_string = mySociety::Config::get('ALLOWED_COBRANDS');
    my @allowed_cobrands = split(/\|/, $allowed_cobrand_string);
    return \@allowed_cobrands;
}

=item url

Given a URL, return a URL with any extra params needed appended to it.

=cut
sub url {
    my ($cobrand, $url, $q, $extra_data) = @_;
    my $handle;
    if ($cobrand){
        $handle = cobrand_handle($cobrand);
    }
    if ( !$cobrand || !$handle || !$handle->can('url')){
        return $url;
    } else{
        return $handle->url($url, $q, $extra_data);
    }
}

=item base_url_for_emails COBRAND

Return the base url to use in links in emails for the cobranded 
version of the site

=cut

sub base_url_for_emails {
    my ($cobrand) = @_;
    my $handle;
    if ($cobrand){
        $handle = cobrand_handle($cobrand);
    }
    if ( !$cobrand ) {
        return mySociety::Config::get('BASE_URL');
    }
    if ( !$handle || ! $handle->can('base_url_for_emails')){
        return "http://" . $cobrand . "." . mySociety::Config::get('WEB_DOMAIN');
    } else {
        return $handle->base_url_for_emails();
    }
}

1;
