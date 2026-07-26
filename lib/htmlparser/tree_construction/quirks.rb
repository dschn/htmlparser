# frozen_string_literal: true

module HTMLParser
  class TreeConstruction
    # §13.2.6.4.1 — DOCTYPE → quirks / limited-quirks mode (§ quirks-mode-doctypes).
    module Quirks
      # Exact public-id matches (ASCII case-insensitive).
      QUIRKS_PUBLIC_IDS = [
        "-//W3O//DTD W3 HTML Strict 3.0//EN//",
        "-/W3C/DTD HTML 4.0 Transitional/EN",
        "HTML"
      ].map(&:downcase).freeze

      # Exact system-id match (ASCII case-insensitive).
      QUIRKS_SYSTEM_IDS = [
        "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd"
      ].map(&:downcase).freeze

      # Public-id prefixes that force quirks mode.
      QUIRKS_PUBLIC_ID_PREFIXES = [
        "+//Silmaril//dtd html Pro v0r11 19970101//",
        "-//AS//DTD HTML 3.0 asWedit + extensions//",
        "-//AdvaSoft Ltd//DTD HTML 3.0 asWedit + extensions//",
        "-//IETF//DTD HTML 2.0 Level 1//",
        "-//IETF//DTD HTML 2.0 Level 2//",
        "-//IETF//DTD HTML 2.0 Strict Level 1//",
        "-//IETF//DTD HTML 2.0 Strict Level 2//",
        "-//IETF//DTD HTML 2.0 Strict//",
        "-//IETF//DTD HTML 2.0//",
        "-//IETF//DTD HTML 2.1E//",
        "-//IETF//DTD HTML 3.0//",
        "-//IETF//DTD HTML 3.2 Final//",
        "-//IETF//DTD HTML 3.2//",
        "-//IETF//DTD HTML 3//",
        "-//IETF//DTD HTML Level 0//",
        "-//IETF//DTD HTML Level 1//",
        "-//IETF//DTD HTML Level 2//",
        "-//IETF//DTD HTML Level 3//",
        "-//IETF//DTD HTML Strict Level 0//",
        "-//IETF//DTD HTML Strict Level 1//",
        "-//IETF//DTD HTML Strict Level 2//",
        "-//IETF//DTD HTML Strict Level 3//",
        "-//IETF//DTD HTML Strict//",
        "-//IETF//DTD HTML//",
        "-//Metrius//DTD Metrius Presentational//",
        "-//Microsoft//DTD Internet Explorer 2.0 HTML Strict//",
        "-//Microsoft//DTD Internet Explorer 2.0 HTML//",
        "-//Microsoft//DTD Internet Explorer 2.0 Tables//",
        "-//Microsoft//DTD Internet Explorer 3.0 HTML Strict//",
        "-//Microsoft//DTD Internet Explorer 3.0 HTML//",
        "-//Microsoft//DTD Internet Explorer 3.0 Tables//",
        "-//Netscape Comm. Corp.//DTD HTML//",
        "-//Netscape Comm. Corp.//DTD Strict HTML//",
        "-//O'Reilly and Associates//DTD HTML 2.0//",
        "-//O'Reilly and Associates//DTD HTML Extended 1.0//",
        "-//O'Reilly and Associates//DTD HTML Extended Relaxed 1.0//",
        "-//SQ//DTD HTML 2.0 HoTMetaL + extensions//",
        "-//SoftQuad Software//DTD HoTMetaL PRO 6.0::19990601::extensions to HTML 4.0//",
        "-//SoftQuad//DTD HoTMetaL PRO 4.0::19971010::extensions to HTML 4.0//",
        "-//Spyglass//DTD HTML 2.0 Extended//",
        "-//Sun Microsystems Corp.//DTD HotJava HTML//",
        "-//Sun Microsystems Corp.//DTD HotJava Strict HTML//",
        "-//W3C//DTD HTML 3 1995-03-24//",
        "-//W3C//DTD HTML 3.2 Draft//",
        "-//W3C//DTD HTML 3.2 Final//",
        "-//W3C//DTD HTML 3.2//",
        "-//W3C//DTD HTML 3.2S Draft//",
        "-//W3C//DTD HTML 4.0 Frameset//",
        "-//W3C//DTD HTML 4.0 Transitional//",
        "-//W3C//DTD HTML Experimental 19960712//",
        "-//W3C//DTD HTML Experimental 970421//",
        "-//W3C//DTD W3 HTML//",
        "-//W3O//DTD W3 HTML 3.0//",
        "-//WebTechs//DTD Mozilla HTML 2.0//",
        "-//WebTechs//DTD Mozilla HTML//"
      ].map(&:downcase).freeze

      # Prefixes that force quirks only when system id is missing/empty.
      QUIRKS_PUBLIC_ID_PREFIXES_IF_SYSTEM_MISSING = [
        "-//W3C//DTD HTML 4.01 Frameset//",
        "-//W3C//DTD HTML 4.01 Transitional//"
      ].map(&:downcase).freeze

      LIMITED_QUIRKS_PUBLIC_ID_PREFIXES = [
        "-//W3C//DTD XHTML 1.0 Frameset//",
        "-//W3C//DTD XHTML 1.0 Transitional//"
      ].map(&:downcase).freeze

      # Prefixes that force limited-quirks only when system id is present and non-empty.
      LIMITED_QUIRKS_PUBLIC_ID_PREFIXES_IF_SYSTEM_PRESENT = [
        "-//W3C//DTD HTML 4.01 Frameset//",
        "-//W3C//DTD HTML 4.01 Transitional//"
      ].map(&:downcase).freeze

      private

      def quirks_mode_for_doctype(token)
        return :quirks if token.force_quirks

        name = (token.name || "").downcase
        return :quirks if name != "html"

        public_id = token.public_identifier
        system_id = token.system_identifier
        # Missing vs empty: empty string is not missing for these checks.
        public_missing = public_id.nil?
        system_missing = system_id.nil?
        pub = public_missing ? "" : public_id.downcase
        sys = system_missing ? "" : system_id.downcase

        return :quirks if QUIRKS_PUBLIC_IDS.include?(pub)
        return :quirks if !system_missing && QUIRKS_SYSTEM_IDS.include?(sys)
        return :quirks if QUIRKS_PUBLIC_ID_PREFIXES.any? { |prefix| pub.start_with?(prefix) }
        if system_missing || sys.empty?
          return :quirks if QUIRKS_PUBLIC_ID_PREFIXES_IF_SYSTEM_MISSING.any? { |prefix| pub.start_with?(prefix) }
        end

        return :limited_quirks if LIMITED_QUIRKS_PUBLIC_ID_PREFIXES.any? { |prefix| pub.start_with?(prefix) }
        unless system_missing || sys.empty?
          if LIMITED_QUIRKS_PUBLIC_ID_PREFIXES_IF_SYSTEM_PRESENT.any? { |prefix| pub.start_with?(prefix) }
            return :limited_quirks
          end
        end

        :no_quirks
      end
    end
  end
end
