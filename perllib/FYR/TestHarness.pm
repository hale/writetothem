#!/usr/bin/perl
#
# TestHarness.pm:
# Functions to support functional tests for WriteToThem
#
# Copyright (c) 2009 UK Citizens Online Democracy. All rights reserved.
# Email: louise@mysociety.org; WWW: http://www.mysociety.org/
#
# $Id: TestHarness.pm,v 1.8 2009-09-30 15:28:31 louise Exp $
#

package FYR::TestHarness;


BEGIN {
    use Exporter ();
    our @ISA = qw(Exporter);
    our @EXPORT_OK = qw(&email_n &name_n &call_fyrqd &set_fyr_date &spin_queue &send_message_to_rep &check_delivered_to_rep &call_handlemail &call_allow_new_survey);
}

use strict;
require 5.8.0;

use FindBin;
use lib "$FindBin::Bin/../../perllib";
use lib "$FindBin::Bin/../../../perllib";
use mySociety::DBHandle qw(dbh);
use mySociety::Config;  
mySociety::Config::set_file('../../conf/general');

#############################################################################
# General functions

sub email_n { my $n = shift; return ($n == 666 ? "this-will-bounce\@" : "fyrharness+$n\@") . mySociety::Config::get('EMAIL_DOMAIN'); }
sub name_n { my $n = shift; return "Cate Constituent $n"; }


# Call fyrqd for one pass
sub call_fyrqd {
    my ($wth, $verbose, $multispawn, $delivery_method) = @_;
    
    if (!defined($delivery_method)){
          $delivery_method = '--email';
    }

    $wth->multi_spawn($multispawn, "./fyrqd --debug --once $delivery_method"
            # . ($verbose > 1 ? qw(--verbose) : ())
        , $verbose) ;
}


# Change the date that all parts of WriteToThem think is today.  Call with no
# parameters to reset it to the actual today.
sub set_fyr_date {
    my ($new_date, $new_time, $verbose) = @_;

    if (defined($new_date)) {
        dbh()->do('delete from debugdate');
        if (defined($new_time)){
            dbh()->do('insert into debugdate (override_today, override_time) values (?,?)', {}, $new_date, $new_time);
        }else{
            dbh()->do('insert into debugdate (override_today) values (?)', {}, $new_date);
        }

    } else {
        dbh()->do('delete from debugdate');
    }
    print "Date changed to $new_date\n" if $verbose > 1;
    dbh()->commit();
}

# Run the fyr queue on many sequential dates
# [note the this is a half-open interval - the first date is the first one
# used, but the last date is one after the last date which is used)
sub spin_queue {
    my ($format_string, $from, $to, $wth, $verbose, $multispawn) = @_;
    for (my $i = $from; $i < $to; $i ++) {
        set_fyr_date(sprintf($format_string, $i), $verbose);
        call_fyrqd($wth, $verbose, $multispawn);
        call_fyrqd($wth, $verbose, $multispawn);
        call_fyrqd($wth, $verbose, $multispawn);
    }
}


sub send_message_to_rep {
    my ($base_url, $wth, $verbose, $multispawn, $who, $postcode, $repname, $fields, $cobrand, $birthday, $reptype, $repnames) = @_;
    $fields->{name} = name_n($who);
    $fields->{writer_email} = email_n($who);
    $fields->{writer_email2} = email_n($who);

    if (!$birthday) {
        # Postcode selection of representative
        my $start_url = $base_url;
        $start_url .= "?cocode=9" if ($cobrand && $cobrand eq "animalaid");
        $wth->browser_get($start_url);
        $wth->browser_check_contents("First, type your UK postcode:");
        $wth->browser_submit_form(form_name => 'postcodeForm',
            fields => { pc => $postcode},
            );
        $wth->browser_check_contents("Now select the representative you'd like to contact");

        if ($repname eq 'all'){
            my $alllink = "Write to all your $reptype";
            $wth->browser_follow_link(text_regex => qr/$alllink/);
        }else{
            $wth->browser_follow_link(text_regex => qr/$repname/);
        }
    } else {
        # House of Lords selection by birthday
        $wth->browser_get($base_url . "/lords");
        $wth->browser_check_contents("Which Lord would you like to write to?");
        $wth->browser_submit_form(form_name => 'dateLordForm',
            fields => { d => $birthday},
            );
        # Postcode gets filled in on letter writing page in Lords case
        $fields->{pc} = $postcode;
    }

    # Fill in a test letter
    $wth->browser_check_contents("Now Write Your Message");
    $wth->browser_check_contents("This is a test version"); # Make sure mail will loop back rather than go to rep
    if ($repname eq 'all'){
        my $one_rep;
        foreach $one_rep (@$repnames){
            $wth->browser_check_contents($one_rep);
        }
    }else{
        $wth->browser_check_contents($repname);
    }
    $wth->browser_submit_form(form_name => 'writeForm',
        fields => $fields, button => 'submitPreview');
    # ... check preview and submit it
    $wth->browser_check_contents('Now Preview The Message');
    $wth->browser_check_contents($fields->{body});
    $wth->browser_submit_form(form_name => 'previewForm', button => 'submitSendFax');
    $wth->browser_check_contents('Nearly Done! Now check your email');

    # TODO: Check message isn't sent early
    # Wait for confirmation email to arrive
    call_fyrqd($wth, $verbose, $multispawn);
    if ($who == 666) {
        # Mail to and from same deliberately invalid address, so will not arrive
        $wth->email_check_none_left();
        # Confirm via database instead, as what we really want to test is MP bounce
        dbh()->do("update message set state = 'ready' where sender_email = ?", {}, email_n($who));
        dbh()->commit();
    } else {
        # Click link in the confirmation email
        my $conf_name;
        if ($repname eq 'all'){
            $conf_name = "your $reptype";
        }else{
            $conf_name = $repname;
        }
        my $confirmation_email = $wth->email_get_containing(
            '%Subject: Please confirm that you want to send a message to %'.$conf_name.
            '%To: "'.name_n($who).'" <'.email_n($who).'>'.
            '%THIS IS A TEST SITE, THE MESSAGE WILL BE SENT TO YOURSELF'.
            '%to confirm that you wish%');
        die "Message confirmation link not found" if ($confirmation_email !~ m#^\s*($base_url.*$)#m);
        print "Message confirm URL is $1\n" if $verbose > 1;
        $wth->email_check_url($1);
        $wth->browser_get($1);
 
        if ($cobrand && $cobrand eq "animalaid") {
            $wth->browser_check_contents("Thank you! You've completed the action for \"Let's stop veal farming for good\".");
        } else {
            $wth->browser_check_contents("All done&hellip; We&rsquo;ll send your message now");
        }   
    }
} 

sub check_delivered_to_rep {
    my ($who, $repname, $extra_check, $wth, $verbose, $multispawn) = @_;

    call_fyrqd($wth, $verbose, $multispawn);
    my $content = $wth->email_get_containing(
        '%Subject: Letter from %'.name_n($who).
        '%To: "%'.$repname.'%" <'.email_n($who).'>'.
        '%From: "'.name_n($who).'" <'.email_n($who).'>'.
        '%'.$extra_check.
        '%Signed with an electronic signature%');

    return $content;
}


# Send one mail to bounce handling script
sub call_handlemail {
    my ($content) = @_;
    my $p = mySociety::TempFiles::pipe_via("./handlemail") or die "failed to call handlemail";
    $p->print($content);
    $p->close();
}

# Clear survey result, so can take survey again
sub call_allow_new_survey {
    my ($email, $wth, $verbose) = @_;
    $wth->multi_spawn(1, "./allow-new-survey $email", $verbose) ;
}
