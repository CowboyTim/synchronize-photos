#!/usr/bin/perl -w

# License
#
# synchronize.pl is distributed under the zlib/libpng
# license, which is OSS (Open Source Software) compliant.
#
# Copyright (C) 2009 Tim Aerts
#
# This software is provided 'as-is', without any express or implied
# warranty.  In no event will the authors be held liable for any damages
# arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
#
# 1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.
#
# Tim Aerts <aardbeiplantje@gmail.com>


use strict; use warnings;

#-------------------------------------------------------------------------------
# Needed modules
#-------------------------------------------------------------------------------

use Pod::Usage;
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);
use File::Path qw(mkpath);
use File::Basename;
use File::Copy;
use File::Find;
use Data::Dumper;

use Gtk2 '-init'; # auto-initializes Gtk2
use Gtk2::GladeXML;


#-------------------------------------------------------------------------------
# Command line options parsing
#-------------------------------------------------------------------------------

my $src_dir           = '/media/usbdisk';
my $target_dir_format = '%Y_%m_%d';
my $target_dir        = (glob('~/fotos'))[0];
my $photo_regex       = qr/\.(JPG|CRW|THM|CR2|MOV)$/i;
my $help              = 0;
my $man               = 0;
GetOptions ("sourcedir=s" => \$src_dir,
            "targetdir=s" => \$target_dir,
            "targetfmt=s" => \$target_dir_format,
            "help|?!"     => \$help,
            "man!"        => \$man)
    or pod2usage(-verbose => 1);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
pod2usage(-exitstatus => 1, 
          -message    => "***ERROR: Please specify a valid source directory\n") 
    if !-d $src_dir;
pod2usage(-exitstatus => 1, 
          -message    => "***ERROR: Please specify a valid target directory\n") 
    if !-d $target_dir;

#-------------------------------------------------------------------------------
# Application
#-------------------------------------------------------------------------------

my $glade_resource_fn = '&DATA';
my $glade_data;
{
  open my $glade_resource, "<$glade_resource_fn";
  local $/ = undef; 
  $glade_data = <$glade_resource>;
  close $glade_resource;
}
my $glade = Gtk2::GladeXML->new_from_buffer($glade_data);
$glade->signal_autoconnect_from_package('main');

my $sum = 0;
my $files = find_files($src_dir, $target_dir, $photo_regex);
if (!keys %{$files}){
    $glade->get_widget('done_dialog')->show_all();
} else {
    $glade->get_widget('main_window')->show_all();
    $sum = 0;
    foreach my $date (keys %{$files}){
        $sum += keys %{$files->{$date}};
    }
    $glade->get_widget('nr_photos')
          ->set_label("A total of $sum photos need to be copied");
}

Gtk2->main();
exit;


#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------

sub find_files {
    my ($src_dir, $target_dir, $regex) = @_;

    my %unique_photos = ();
    my %files = ();
    my $wanted = sub {
        my $flnm = $_;
        my $file = $File::Find::name;
        if ($file =~ $regex and -f $file){
            my $mtime = strftime $target_dir_format, gmtime((stat($file))[9]);

            # mark file for copying if it doesn't exist
            my $target_file = "$target_dir/$mtime/$flnm";
            if (!-e $target_file or -s $target_file == 0){

                # raw pictures are saved in 2 files, we want the unique number
                # of photos here
                $flnm =~ s/\..*$//;

                # mark the file for copying, index by date
                print "$file is taken at $mtime\n"
                    if !exists $files{$mtime}{$flnm};
                $files{$mtime}{$flnm}{$file} = $target_file;
            }
        }
    };
    find($wanted, $src_dir);

    return \%files;
}

#----------------------------------------------------------------------
# Signal handlers, connected to signals we defined using glade-2
#----------------------------------------------------------------------

sub on_copy_button_clicked {

    my $progressbar = $glade->get_widget('progressbar');
    my $current_photo_nr = $glade->get_widget('current_photo_nr');
    my $src_file = $glade->get_widget('source_file');
    my $tgt_file = $glade->get_widget('target_file');
    my $progress = 0;
    my $copy_ok = 0;
    my $response = 0;
    foreach my $date (sort keys %{$files}){
        foreach my $photo (sort keys %{$files->{$date}}){
            eval {
                foreach my $source_file (sort keys %{$files->{$date}{$photo}}){

                    my $target_file = $files->{$date}{$photo}{$source_file};

                    # make that directory if it doesn't exist
                    my $new_date_dir = dirname($target_file);
                    if (!-d $new_date_dir){
                        eval { mkpath($new_date_dir) };
                        handle_IO_error(\$response, $@) if $@;
                    }

                    $src_file->set_label($source_file);
                    $tgt_file->set_label($target_file);
                    $current_photo_nr->set_label($progress);

                    Gtk2->main_iteration() while ( Gtk2->events_pending() );

                    eval {
                        copy($source_file, $target_file, 8388608)
                            or die "Copy from $source_file to $target_file failed:$!\n";
                    };
                    handle_IO_error(\$response, $@) if $@;
                }
            };
            $copy_ok++ if !$@;
            $progress++;
            $progressbar->set_fraction($progress/$sum);
            Gtk2->main_iteration() while ( Gtk2->events_pending() );
        }
    }
    $glade->get_widget('done_label')
          ->set_label("A total of $copy_ok photos were copied");
    $glade->get_widget('done_dialog')
          ->show_all();
}

sub on_cancel_button_clicked {
    Gtk2->main_quit();
    exit;
}

sub handle_IO_error {
    my ($response, $error) = @_;
    chomp($error);
    my $dialog = $glade->get_widget('copy_error');
    $glade->get_widget('error_label')->set_label($error);
    if ($$response != 1){
        $$response = $dialog->run();
    }
    if ($$response == 2){
        on_cancel_button_clicked();
    }
    $dialog->hide();
    die "$error\n";
}

# Handles window-manager-quit: shuts down gtk2 lib
sub on_main_window_delete_event {
    Gtk2->main_quit();
    exit;
}


=head1 NAME

synchronize.pl - Synchronizes photos on disk

=head1 SYNOPSIS

synchronize.pl [options]

=head1 OPTIONS

=over 4

=item B<--help|-?>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--sourcedir F<E<lt>source directoryE<gt>>>

The base source directory where the photos are to be found. This is usually on
a compact flash card that is mounted.

=item B<--targetdir F<E<lt>target directoryE<gt>>>

The target directory where the fotos will be copied to. In this dir, subdirs
are made by date, in the format specified by the --targetfmt option. Default
this is ~/fotos if it exists.

=item B<--targetfmt F<E<lt>target sub directory formatE<gt>>>

This is the target directory's foto subdir format where the fotos are to be
copied to. Default, this is YYYY_MM_DD.

=back

=head1 DESCRIPTION

=cut

__DATA__
<?xml version="1.0" standalone="no"?> <!--*- mode: xml -*-->
<!DOCTYPE glade-interface SYSTEM "http://glade.gnome.org/glade-2.0.dtd">

<glade-interface>

<widget class="GtkDialog" id="done_dialog">
  <property name="title" translatable="yes">photo copy progress</property>
  <property name="type">GTK_WINDOW_TOPLEVEL</property>
  <property name="window_position">GTK_WIN_POS_NONE</property>
  <property name="modal">True</property>
  <property name="resizable">False</property>
  <property name="destroy_with_parent">True</property>
  <property name="decorated">True</property>
  <property name="skip_taskbar_hint">False</property>
  <property name="skip_pager_hint">False</property>
  <property name="type_hint">GDK_WINDOW_TYPE_HINT_DIALOG</property>
  <property name="gravity">GDK_GRAVITY_NORTH_WEST</property>
  <property name="focus_on_map">True</property>
  <property name="urgency_hint">False</property>
  <property name="has_separator">True</property>

  <child internal-child="vbox">
    <widget class="GtkVBox" id="dialog-vbox1">
      <property name="visible">True</property>
      <property name="homogeneous">False</property>
      <property name="spacing">0</property>

      <child internal-child="action_area">
	<widget class="GtkHButtonBox" id="dialog-action_area1">
	  <property name="visible">True</property>
	  <property name="layout_style">GTK_BUTTONBOX_END</property>

	  <child>
	    <widget class="GtkButton" id="closebutton1">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label">gtk-close</property>
	      <property name="use_stock">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">-7</property>
	      <signal name="clicked" handler="on_cancel_button_clicked" last_modification_time="Sun, 06 Aug 2006 14:54:51 GMT"/>
	    </widget>
	  </child>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">False</property>
	  <property name="fill">True</property>
	  <property name="pack_type">GTK_PACK_END</property>
	</packing>
      </child>

      <child>
	<widget class="GtkLabel" id="done_label">
	  <property name="width_request">0</property>
	  <property name="height_request">0</property>
	  <property name="visible">True</property>
	  <property name="label" translatable="yes">No photos need to be copied</property>
	  <property name="use_underline">False</property>
	  <property name="use_markup">False</property>
	  <property name="justify">GTK_JUSTIFY_LEFT</property>
	  <property name="wrap">False</property>
	  <property name="selectable">False</property>
	  <property name="xalign">0.5</property>
	  <property name="yalign">0.5</property>
	  <property name="xpad">20</property>
	  <property name="ypad">20</property>
	  <property name="ellipsize">PANGO_ELLIPSIZE_NONE</property>
	  <property name="width_chars">-1</property>
	  <property name="single_line_mode">False</property>
	  <property name="angle">0</property>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">False</property>
	  <property name="fill">False</property>
	</packing>
      </child>
    </widget>
  </child>
</widget>

<widget class="GtkDialog" id="main_window">
  <property name="width_request">0</property>
  <property name="height_request">0</property>
  <property name="title" translatable="yes">photo copy progress</property>
  <property name="type">GTK_WINDOW_TOPLEVEL</property>
  <property name="window_position">GTK_WIN_POS_NONE</property>
  <property name="modal">False</property>
  <property name="resizable">False</property>
  <property name="destroy_with_parent">False</property>
  <property name="decorated">True</property>
  <property name="skip_taskbar_hint">False</property>
  <property name="skip_pager_hint">False</property>
  <property name="type_hint">GDK_WINDOW_TYPE_HINT_DIALOG</property>
  <property name="gravity">GDK_GRAVITY_NORTH_WEST</property>
  <property name="focus_on_map">True</property>
  <property name="urgency_hint">False</property>
  <property name="has_separator">True</property>

  <child internal-child="vbox">
    <widget class="GtkVBox" id="dialog-vbox2">
      <property name="visible">True</property>
      <property name="homogeneous">False</property>
      <property name="spacing">5</property>

      <child internal-child="action_area">
	<widget class="GtkHButtonBox" id="dialog-action_area2">
	  <property name="visible">True</property>
	  <property name="layout_style">GTK_BUTTONBOX_END</property>

	  <child>
	    <widget class="GtkButton" id="cancel_button">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label">gtk-cancel</property>
	      <property name="use_stock">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">-6</property>
	      <signal name="clicked" handler="on_cancel_button_clicked" last_modification_time="Tue, 15 Aug 2006 14:39:11 GMT"/>
	    </widget>
	  </child>

	  <child>
	    <widget class="GtkButton" id="copy_button">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label">gtk-ok</property>
	      <property name="use_stock">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">-5</property>
	      <signal name="clicked" handler="on_copy_button_clicked" last_modification_time="Tue, 15 Aug 2006 14:38:58 GMT"/>
	    </widget>
	  </child>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">False</property>
	  <property name="fill">True</property>
	  <property name="pack_type">GTK_PACK_END</property>
	</packing>
      </child>

      <child>
	<widget class="GtkLabel" id="nr_photos">
	  <property name="width_request">0</property>
	  <property name="height_request">0</property>
	  <property name="visible">True</property>
	  <property name="label" translatable="yes"></property>
	  <property name="use_underline">True</property>
	  <property name="use_markup">False</property>
	  <property name="justify">GTK_JUSTIFY_LEFT</property>
	  <property name="wrap">False</property>
	  <property name="selectable">False</property>
	  <property name="xalign">0.5</property>
	  <property name="yalign">0.5</property>
	  <property name="xpad">0</property>
	  <property name="ypad">0</property>
	  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
	  <property name="width_chars">-1</property>
	  <property name="single_line_mode">True</property>
	  <property name="angle">0</property>
	</widget>
	<packing>
	  <property name="padding">5</property>
	  <property name="expand">False</property>
	  <property name="fill">False</property>
	</packing>
      </child>

      <child>
	<widget class="GtkProgressBar" id="progressbar">
	  <property name="width_request">450</property>
	  <property name="height_request">16</property>
	  <property name="visible">True</property>
	  <property name="orientation">GTK_PROGRESS_LEFT_TO_RIGHT</property>
	  <property name="fraction">0</property>
	  <property name="pulse_step">0.10000000149</property>
	  <property name="text" translatable="yes">copy progress</property>
	  <property name="ellipsize">PANGO_ELLIPSIZE_NONE</property>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">True</property>
	  <property name="fill">True</property>
	</packing>
      </child>

      <child>
	<widget class="GtkAlignment" id="alignment1">
	  <property name="visible">True</property>
	  <property name="xalign">0.5</property>
	  <property name="yalign">0.5</property>
	  <property name="xscale">1</property>
	  <property name="yscale">1</property>
	  <property name="top_padding">0</property>
	  <property name="bottom_padding">0</property>
	  <property name="left_padding">0</property>
	  <property name="right_padding">0</property>

	  <child>
	    <widget class="GtkTable" id="table1">
	      <property name="border_width">10</property>
	      <property name="visible">True</property>
	      <property name="n_rows">3</property>
	      <property name="n_columns">2</property>
	      <property name="homogeneous">False</property>
	      <property name="row_spacing">10</property>
	      <property name="column_spacing">10</property>

	      <child>
		<widget class="GtkLabel" id="source_file">
		  <property name="width_request">0</property>
		  <property name="height_request">0</property>
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">&lt;none yet&gt;</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">True</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">1</property>
		  <property name="right_attach">2</property>
		  <property name="top_attach">1</property>
		  <property name="bottom_attach">2</property>
		  <property name="y_options"></property>
		</packing>
	      </child>

	      <child>
		<widget class="GtkLabel" id="target_file">
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">&lt;none yet&gt;</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">True</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">1</property>
		  <property name="right_attach">2</property>
		  <property name="top_attach">2</property>
		  <property name="bottom_attach">3</property>
		  <property name="y_options"></property>
		</packing>
	      </child>

	      <child>
		<widget class="GtkLabel" id="label23">
		  <property name="width_request">100</property>
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">copying photo</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">True</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">0</property>
		  <property name="right_attach">1</property>
		  <property name="top_attach">0</property>
		  <property name="bottom_attach">1</property>
		  <property name="x_options">fill</property>
		  <property name="y_options"></property>
		</packing>
	      </child>

	      <child>
		<widget class="GtkLabel" id="label19">
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">Source file</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">True</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">0</property>
		  <property name="right_attach">1</property>
		  <property name="top_attach">1</property>
		  <property name="bottom_attach">2</property>
		  <property name="x_options">fill</property>
		  <property name="y_options"></property>
		</packing>
	      </child>

	      <child>
		<widget class="GtkLabel" id="label20">
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">Target file</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">True</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">0</property>
		  <property name="right_attach">1</property>
		  <property name="top_attach">2</property>
		  <property name="bottom_attach">3</property>
		  <property name="x_options">fill</property>
		  <property name="y_options"></property>
		</packing>
	      </child>

	      <child>
		<widget class="GtkLabel" id="current_photo_nr">
		  <property name="width_request">0</property>
		  <property name="height_request">0</property>
		  <property name="visible">True</property>
		  <property name="label" translatable="yes">0</property>
		  <property name="use_underline">False</property>
		  <property name="use_markup">False</property>
		  <property name="justify">GTK_JUSTIFY_LEFT</property>
		  <property name="wrap">False</property>
		  <property name="selectable">False</property>
		  <property name="xalign">0.5</property>
		  <property name="yalign">0.5</property>
		  <property name="xpad">0</property>
		  <property name="ypad">0</property>
		  <property name="ellipsize">PANGO_ELLIPSIZE_START</property>
		  <property name="width_chars">-1</property>
		  <property name="single_line_mode">False</property>
		  <property name="angle">0</property>
		</widget>
		<packing>
		  <property name="left_attach">1</property>
		  <property name="right_attach">2</property>
		  <property name="top_attach">0</property>
		  <property name="bottom_attach">1</property>
		  <property name="x_options">fill</property>
		  <property name="y_options"></property>
		</packing>
	      </child>
	    </widget>
	  </child>
	</widget>
	<packing>
	  <property name="padding">5</property>
	  <property name="expand">False</property>
	  <property name="fill">True</property>
	</packing>
      </child>
    </widget>
  </child>
</widget>

<widget class="GtkDialog" id="copy_error">
  <property name="title" translatable="yes">Error</property>
  <property name="type">GTK_WINDOW_TOPLEVEL</property>
  <property name="window_position">GTK_WIN_POS_NONE</property>
  <property name="modal">True</property>
  <property name="resizable">False</property>
  <property name="destroy_with_parent">True</property>
  <property name="decorated">True</property>
  <property name="skip_taskbar_hint">False</property>
  <property name="skip_pager_hint">False</property>
  <property name="type_hint">GDK_WINDOW_TYPE_HINT_DIALOG</property>
  <property name="gravity">GDK_GRAVITY_NORTH_WEST</property>
  <property name="focus_on_map">True</property>
  <property name="urgency_hint">True</property>
  <property name="has_separator">True</property>

  <child internal-child="vbox">
    <widget class="GtkVBox" id="dialog-vbox3">
      <property name="visible">True</property>
      <property name="homogeneous">False</property>
      <property name="spacing">0</property>

      <child internal-child="action_area">
	<widget class="GtkHButtonBox" id="dialog-action_area3">
	  <property name="visible">True</property>
	  <property name="layout_style">GTK_BUTTONBOX_END</property>

	  <child>
	    <widget class="GtkButton" id="ignore_button">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label" translatable="yes">ignore</property>
	      <property name="use_underline">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">0</property>
	    </widget>
	  </child>

	  <child>
	    <widget class="GtkButton" id="ignore_all_button">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label" translatable="yes">ignore all</property>
	      <property name="use_underline">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">1</property>
	    </widget>
	  </child>

	  <child>
	    <widget class="GtkButton" id="cancel_button">
	      <property name="visible">True</property>
	      <property name="can_default">True</property>
	      <property name="can_focus">True</property>
	      <property name="label" translatable="yes">cancel</property>
	      <property name="use_underline">True</property>
	      <property name="relief">GTK_RELIEF_NORMAL</property>
	      <property name="focus_on_click">True</property>
	      <property name="response_id">2</property>
	      <signal name="clicked" handler="on_cancel_button_clicked" last_modification_time="Tue, 15 Aug 2006 15:57:47 GMT"/>
	    </widget>
	  </child>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">False</property>
	  <property name="fill">True</property>
	  <property name="pack_type">GTK_PACK_END</property>
	</packing>
      </child>

      <child>
	<widget class="GtkLabel" id="error_label">
	  <property name="width_request">0</property>
	  <property name="height_request">0</property>
	  <property name="visible">True</property>
	  <property name="label" translatable="yes">No error</property>
	  <property name="use_underline">False</property>
	  <property name="use_markup">False</property>
	  <property name="justify">GTK_JUSTIFY_LEFT</property>
	  <property name="wrap">False</property>
	  <property name="selectable">False</property>
	  <property name="xalign">0.5</property>
	  <property name="yalign">0.5</property>
	  <property name="xpad">20</property>
	  <property name="ypad">20</property>
	  <property name="ellipsize">PANGO_ELLIPSIZE_NONE</property>
	  <property name="width_chars">-1</property>
	  <property name="single_line_mode">False</property>
	  <property name="angle">0</property>
	</widget>
	<packing>
	  <property name="padding">0</property>
	  <property name="expand">True</property>
	  <property name="fill">True</property>
	</packing>
      </child>
    </widget>
  </child>
</widget>

</glade-interface>
