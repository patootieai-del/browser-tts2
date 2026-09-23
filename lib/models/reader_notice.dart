enum NoticeKind {
  nextNotFound,
  nextNotClickable,
  nextNoChange,
  nextTimeout,
  nextEmpty,
  noRule,
}

class ReaderNotice {
  ReaderNotice(this.kind, this.message, this.shortText);

  final NoticeKind kind;
  final String message; // shown in the dialog
  final String shortText; // shown in the media notification

  bool get canFix => kind != NoticeKind.nextTimeout;

  factory ReaderNotice.of(NoticeKind k, [String? reason]) => switch (k) {
        NoticeKind.nextNotFound => ReaderNotice(
            k,
            'The next-chapter button was not found on this page. Auto-read has stopped. '
                'The story may have ended, or the site layout changed.',
            'next button not found'),
        NoticeKind.nextNotClickable => ReaderNotice(
            k,
            'The next-chapter button is no longer clickable'
                '${reason == null ? '' : ' ($reason)'}. Auto-read has stopped.',
            'next button not clickable'),
        NoticeKind.nextNoChange => ReaderNotice(
            k,
            'The next-chapter button was clicked, but the page content did not change. '
                'Auto-read has stopped.',
            'page did not change'),
        NoticeKind.nextTimeout => ReaderNotice(
            k,
            'The next chapter took too long to load. Auto-read has stopped.',
            'next chapter timed out'),
        NoticeKind.nextEmpty => ReaderNotice(
            k,
            'The next page loaded, but no readable text was found. Auto-read has stopped.',
            'no readable text'),
        NoticeKind.noRule => ReaderNotice(
            k,
            'No next-chapter button is saved for this site. Open the ⋮ menu and choose '
                '"Set next-chapter button".',
            'no next button saved'),
      };
}
