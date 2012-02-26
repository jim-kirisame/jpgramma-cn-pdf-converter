#!/usr/bin/perl

use strict;
use warnings;
use feature qw/say switch/;
use encoding 'utf8';
use utf8;

use WWW::Mechanize;
use HTML::TreeBuilder;
use URI;
use GD;
use Carp;

our $LATEXPRELUDE = <<END;
\\documentclass[a4paper,11pt,twoside]{report}
\\usepackage{taekim}
\\title{Japanese Grammar Guide}
\\author{Tae Kim}
\\begin{document}
\\tkbegin
END
our $LATEXPOSTLUDE = <<END;
\\end{document}
END

binmode STDOUT, ':utf8';

my $output = "tmp.tex";
open(OUT, '>', $output) or die "Opening $output failed: $! $?";

OUT->autoflush(1);
$| = 1;

my $mech = new WWW::Mechanize;
$mech->get('http://www.guidetojapanese.org/learn/grammar');
my $tree = new HTML::TreeBuilder;
$tree->parse_content($mech->content);
my $node = $tree->look_down("_tag", "h2", sub { $_[0]->as_text() eq 'Table of Contents' } )->right;

binmode OUT, ':utf8';
print OUT $LATEXPRELUDE;
#process_url('http://www.guidetojapanese.org/learn/grammar/past_tense', 0, *OUT, "Dingens");
walk_toc($node, 0, *OUT);
print OUT $LATEXPOSTLUDE;
close(OUT);

$tree->delete();

sub walk_toc {
	my ($tree, $level, $outfile) = @_;

	my @nodes = $tree->content_list();
	foreach my $node (@nodes) {
		my $tag = $node->tag;
		if ($tag eq 'li') {
			walk_toc($node, $level, $outfile);
		} elsif ($tag eq 'ol' or $tag eq 'ul') {
			walk_toc($node, $level + 1, $outfile);
		} elsif ($tag eq 'a') {
			my $text = $node->as_text();
			# Skip exercises for now
			next if ($text =~ m/\bExercises\s*$/);
			say "+ " x ($level + 1), $text;
			process_url($node->attr("href"), $level, $outfile, $text);
		} else {
			carp "Unknown TOC tag $tag";
		}
	}
}

sub process_url {
	my ($url, $level, $outfile, $title) = @_;
#	say "Processing: $url";
	my $identifier;
	$identifier = $1 if ($url =~ m@/([^/]+?)$@);
	open(PARTOUT, '>', "$identifier.tex") or die "Opening $identifier.tex failed: $! $?";
	binmode PARTOUT, ':utf8';
	my $tree = new HTML::TreeBuilder;
	my $mech = new WWW::Mechanize;
	$mech->get($url);
	my $htmlcontent = $mech->content;
	#$htmlcontent =~ s#<br ?/>\s*?(\n|\r|\n\r)#<br />#g;
#	$htmlcontent =~ s#<script type="text/javascript".*?>.*?</script>##g;
	# hiragana, katakana and kanji pages have this in the middle of the content, HTML::TreeBuilder freaks out then
	$htmlcontent =~ s#<link .*?/>##g;
	# XeTeX seems to have some issues with jp-style brackets on paragraph begin
	$htmlcontent =~ tr#（）#()#;
#	print $htmlcontent;
	$tree->parse_content($htmlcontent);
	#$tree->dump;
	my $content = $tree->look_down( "_tag", "div", "class", "content clear-block" );
#	$content->dump;
	say PARTOUT make_heading($level, $title);
	say PARTOUT tree_to_latex($content, $level + 1);
	say $outfile "\\input{$identifier}";
	$tree->delete();
	close(PARTOUT);
}

sub tree_to_latex {
	my ($tree, $level, $context) = @_;

	my $latex = "";
	my $close = 0;
	my $newline = 0;
	my $remsubtxt = 0;
	my $end;
	my $after = "";
	my $encaps_text_in;
	my $class = $tree->attr("class") // ""; # /
	my @classes = split(/\s+/, $class);
	my $id    = $tree->attr("id") // ""; # /
	my $tag   = $tree->tag;

	return "" if elem_in_list('dontprint', \@classes);

	given ($tag) {
		when ("h2")           { return make_node_heading($level, $tree); }
		when ("h3")           { return make_node_heading($level + 1, $tree); }
		when (["b","strong"]) { $encaps_text_in = "\\textbf{"; }
		when ("i")            { $encaps_text_in = "\\textit{"; }
		when ("em")           { $encaps_text_in = "{\\color{highlight}"; }
		when ("u")            { $encaps_text_in = "\\uline{"; }
		when ("strike")       { $encaps_text_in = "\\sout{"; }
		when ("br")           { return (exists $$context{'table_cols'}) ? " " : "\\\\\n"; }
		when ("span") {
			# class=popup is missing here
			break if ($tree->as_text() eq '方');
			if (elem_in_list('summary', \@classes)) {
				$latex .= "\\textbf{";
				$close = 1;
			} elsif (elem_in_list('popup', \@classes) or $class eq '') {
			} else {
				carp "Unknown span type $class";
			}
		}
		when ("div") {
			# JS content on hiragana pages
			return "" if ($id eq 'basic-modal-content');
			if (elem_in_list('sumbox', \@classes) or elem_in_list('note', \@classes)) {
				my $title = "Note";
				my $sumelem = $tree->look_down('_tag', 'span', 'class', 'summary');
				if ($sumelem) {
					$title = get_node_as_text($sumelem);
					$sumelem->right->delete() if ($sumelem->right->tag eq 'br');
					$sumelem->delete();
				}
				$latex .= "\\begin{tkbasebox}%\n\\node[tkbox](box){%\n\\begin{tkinsidebox}%\n";
				$after = "%\n\\end{tkinsidebox}%\n};%\n\\tkboxheader{$title}%\n\\end{tkbasebox}\n";
			} elsif (elem_in_list('node-author', \@classes) or elem_in_list('book-navigation', \@classes)) {
				return "";
			} elsif (elem_in_list('content', \@classes) and elem_in_list('clear-block', \@classes)) {
			} else {
				carp "Unknown div type $class";
				$tree->dump;
			}
		}
		when ("img") {
                        if (check_img($tree->attr('src'))) {
                                return "\\begin{center}\\includegraphics[width=0.5\\textwidth]{" . download_img($tree->attr('src')) . "}\\end{center}";
                        }
		}
		when ("ul") {
			$latex .= "\\begin{itemize}\n";
			$end = "itemize";
		}
		when ("ol") {
			$latex .= "\\begin{enumerate}\n";
			$end = "enumerate";
		}
		when ("li") {
			$latex .= "\\item ";
			$newline = 1;
		}
		when ("p") {
			$newline = 2;
		}
		when ("font") {
			if ($tree->attr('size') and $tree->attr('size') eq '-1') {
				$encaps_text_in = "\\small{";
			} else {
				carp "Font tag with unknown options"; $tree->dump();
			}
		}
		when ("center") {
			return "" if (get_node_as_text($tree) eq "");
			$latex .= "\\begin{center}\n";
			$end = "center";
#			return "\\hfill " . escape_tex($tree->as_text()) . " \\hfill\\hbox{}\n";
		}
		when ("table") {
			# Analyze layout
			my @subtables = $tree->look_down('_tag', 'table');
			# Only give horizontal lines to tables which do not have subtables
			$$context{'table_has_hlines'} = (scalar @subtables <= 1); # Own tag also counts as table
			# Count one row of columns
			my @trs = get_node_sub_tags($tree, "tr");
			my @tds = find_first_subs_in_array(\@trs, ["td", "th"]);
			my @specs;
			push @specs, "c" foreach (@tds);
			if (elem_in_list('scale-to-page-width', \@classes)) {
				$latex .= "\\resizebox{\\textwidth}{!}{";
				$close = 1;
			# Center toplevel table
			} elsif (not exists($$context{'table_cols'})) {
				$latex .= "\\begin{center}\n";
				$after = "\\end{center}";
			}
			$latex .= "\\begin{tabular}[t]{" . ($tree->attr('border') ? join("|", @specs) : "@specs") . "}\n";
			$$context{'table_cols'} = scalar @tds;
			$end = "tabular";

			# Scan for <br>s
			fix_table_brs($tree);
		}
		when ("caption") {
			$encaps_text_in = "\\multicolumn{" . $$context{'table_cols'} . "}{c}{\\cellcolor{tablecaption}";
			$after = " \\\\\n\\hline ";
		}
		when ("tr") {
			$after  = "\\\\\n";
			$after .= "\\hline " if ($tree->attr("last") and $$context{'table_has_hlines'});
		}
		when ("td") {
			$after = " & " if ($$context{'nodenum'} < ($$context{'table_cols'} - 1));
		}
		when ("th") {
			$encaps_text_in = "\\cellcolor{tableheader}\\textbf{";
			$after = " & " if ($$context{'nodenum'} < ($$context{'table_cols'} - 1));
		}
		when (["script"]) {
			return "";
		}
		when ("a") {
			my $href = $tree->attr('href') // ''; # /
			my $uri = URI->new($href);
			if ($href =~ m@^https?://@) {
				$encaps_text_in = "\\href{" . escape_tex($uri->as_string, 1) . "}{";
				if ($uri->host ne 'guidetojapanese.org' and $uri->host ne 'www.guidetojapanese.org') {
					$after = " (\\url{" . escape_tex($uri->as_string, 1) . "})";
				}
			}
		}
		default {
			carp "Unknown tag " . $tag;
			return "";
		}
	}
	$latex .= "\\renewcommand{\\labelitemi}{}\n" if (($tag eq 'ul' or $tag eq 'ol' ) and elem_in_list('plain', \@classes));

	if ($encaps_text_in) {
		my $text = get_node_as_text($tree);
		return $encaps_text_in . escape_tex($text) . "}" . $after . ("\n" x $newline);
	}

	my @nodes = $tree->content_list();
	my $nodenum = 0;
	foreach my $node (@nodes) {
		if (ref $node) {
			$$context{'nodenum'} = $nodenum++;
			# Create copy of context
			my %ncontext = %$context;
			$latex .= tree_to_latex($node, $level, \%ncontext);
		} else {
			$latex .= escape_tex($node);
		}
	}

	if ($end) {
		$latex .= "\\end{$end}\n";
	}
	$latex .= "}" x $close;
	$latex .= $after;
	$latex .= "\n" x $newline;

	return $latex;
}

sub make_heading {
	my ($level, $text) = @_;

	my @LATEXLEVEL = ('chapter', 'section', 'subsection', 'subsubsection');
	my $cmd = $LATEXLEVEL[$level];
	my $ret = "";
	my $ntext = $text;
	if ($level < 3) {
		# Strip content in braces for page title and TOC
		$ntext =~ s/\s+?[(（].*?[)）]$//;
	}

	$ret = "\\" . $cmd . (($ntext ne $text) ? ("[" . escape_tex($ntext) . "]") : '') . "{" . escape_tex($text) . "}\n";
	return $ret;
}

sub make_node_heading {
	my ($level, $node) = @_;
	return make_heading($level, get_node_as_text($node));
}

# Mostly copied from HTML::Element::as_text
sub get_node_as_text {
	# Yet another iteratively implemented traverser
	my($this,%options) = @_;
	my $skip_dels = $options{'skip_dels'} || 0;
	my(@pile) = ($this);
	my $tag;
	my $text = '';
	while(@pile) {
		if(!defined($pile[0])) { # undef!
			# no-op
		} elsif(!ref($pile[0])) { # text bit!  save it!
			$text .= shift @pile;
		} else { # it's a ref -- traverse under it
			unshift @pile, @{$this->{'_content'} || []}
			unless
				($tag = ($this = shift @pile)->{'_tag'}) eq 'style'
				or $tag eq 'script'
				# Only difference from HTML::Element::as_text
				or elem_in_list('dontprint', [split(/\s+/, $this->attr('class') // '')]) # /
				or ($skip_dels and $tag eq 'del');
		}
	}
	return $text;
}

sub escape_tex {
	my ($text, $mode) = @_;
	$mode //= 0; # /
	my @REPLACE = (
		[ '{' , '\\{' ],
		[ '}' , '\\}' ],
		[ '%' , '\\%' ],
		[ '#' , '\\#' ],
		# \jpb allows LaTeX to do a linebreak
		[ '、', '、{\\jpb}' ],
		[ '「', '{\\jpb}「' ],
		[ '」', '」{\\jpb}' ],
	);
	if ($mode == 0) {
		unshift @REPLACE,
			[ '\\\\', '\\textbackslash' ];
		push @REPLACE, (
			[ '_' , '\\_' ],
			[ '\\$', '\\$' ],
			[ '\\^' , '\\^' ],
			[ '~' , '\\~{}' ],
			[ '&', '\\&' ],
			[ '>' , '{\\textgreater}' ],
			[ '<' , '{\\textless}' ],
			[ '\\|', '{\\textbar}' ],
		);
	}
	foreach my $c (@REPLACE) {
		my ($a, $b) = @$c;
		$text =~ s/$a/$b/g;
	}
	return $text;
}

sub elem_in_list {
	my ($e, $l) = @_;
	return ($e eq $l) unless (ref $l);
	foreach my $i (@$l) { return 1 if ($i eq $e); }
	return 0;
}

sub get_node_sub_tags {
	my ($node, $tags) = @_;
	return grep { ref $_ and elem_in_list($_->tag, $tags) } $node->content_list;
}

sub find_first_subs_in_array {
	my ($array, $tags) = @_;
	foreach my $elem (@$array) {
		my @subs = $elem->content_list;
		my @nsubs = get_node_sub_tags($elem, $tags);
		return @subs if (scalar @subs == scalar @nsubs);
	}
	croak "No sub tag line matching @$tags detected";
}

# LaTeX does not allow line breaks in table columns not in paragraph mode
# This function splits all brs in table cells up into new table rows
sub fix_table_brs {
	my ($table) = @_;

	# Objectify so we can work on text nodes
	$table->objectify_text;

	my @rows = get_node_sub_tags($table, "tr");
	# Iterate over all rows
	foreach my $row (@rows) {
		my @cols = get_node_sub_tags($row, ["td", "th"]);
		# Temporary storage for additional rows
		my @newrows;
		# Column number
		my $ncol = 0;
		# Iterate over all columns
		foreach my $col (@cols) {
			my @brs = get_node_sub_tags($col, "br");
			# Line break number
			my $nbr = 0;
			# Iterate over all linebreaks
			foreach my $br (@brs) {
				# Create new temporary row if necessary
				if (scalar @newrows <= $nbr) {
					my $e = new HTML::Element('tr');
					# Push empty columns
					$e->push_content(new HTML::Element('td')) foreach (0..($ncol - 1));
					push @newrows, $e;
				}
				my $newrow = $newrows[$nbr];
				# Detach elements following the br from their original position
				my @right = $br->right;
				$_->detach() foreach (@right);
				# Create a new column
				my $newcol = new HTML::Element($col->tag);
				# Insert detached elements into the column
				$newcol->push_content(@right);
				# Insert the column in the temporray new row
				$newrow->push_content($newcol);
				# Delete the now unneeded linebreak
				$br->delete();
				$nbr++;
			}
			# Push empty columns for line breaks not present in this column
			$newrows[$_]->push_content(new HTML::Element($col->tag)) foreach (($nbr)..(scalar @newrows - 1));
			$ncol++;
		}
		# Insert temporary rows into table
		$row->postinsert($_) foreach (@newrows);

		# Mark last row of a group
		my $lastrow = $row;
		if (@newrows) {
			$lastrow = $newrows[-1];
		}
		$lastrow->attr("last", 1);
	}

	# De-objectify now that the work is done
	$table->deobjectify_text();
}

sub print_status {
	my ($s, $f) = @_;
	if ($f) {
		printf "%20s: %-30s", $f, $s;
	} else {
		printf " " x 22 . "%-30s", $s;
	}
}

sub print_status_done {
	say chr(0x1B) . "[1;32mDone!" . chr(0x1B) . "[0m";
}

sub check_img {
        my ($url) = @_;
	if ($url =~ m#^/#) {
		$url = "http://www.guidetojapanese.org$url";
	}
	my $uri = new URI($url);
	my @seg = $uri->path_segments;
	my $filename = $seg[-1];

        # Add your ignores here
        if ($filename eq "play.png") { return 0; }
        return 1;
}

sub download_img {
	my ($url) = @_;
	if ($url =~ m#^/#) {
		$url = "http://www.guidetojapanese.org$url";
	}
	my $uri = new URI($url);
	my @seg = $uri->path_segments;
	my $filename = $seg[-1];
	my $new_filename = $filename;
	my $convert = 0;
	if ($filename =~ m/\.gif$/) {
		$new_filename = "$filename.png";
		$convert = 1;
	}
	if (-e $new_filename) {
		printf "%20s: Skipped\n", $filename;
		return $new_filename;
	}
	my $mech = WWW::Mechanize->new( autocheck => 1 );
	print_status("Downloading...", $filename);

	$mech->get($url);
	print_status_done();
	my $data = $mech->content;
	if ($convert) {
		print_status("Converting to PNG...");
		my $pic = GD::Image->newFromGifData($data);
		$data = $pic->png;
		print_status_done();
	}
	print_status("Writing content...");
	open(IMGOUT, ">", "$new_filename") or die "Opening $new_filename failed: $! $?";
	binmode IMGOUT;
	print IMGOUT $data;
	close(IMGOUT);
	print_status_done();

	return $new_filename;
}


