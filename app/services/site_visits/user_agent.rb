# Dispositivo, navegador e sistema de uma visita, e se o user agent é de robô. Parser simples, feito
# para os poucos casos que importam no site; o que não reconhece vira "Outro".
#
#   SiteVisits::UserAgent.new(ua, screen_width: 390).device_type  # => "mobile"
module SiteVisits
  class UserAgent
    # "(?<!cu)": celulares Cubot ("CUBOT X30") não são robôs.
    BOT = /(?<!cu)bot\b|bot\/|crawl|spider|slurp|headless|phantomjs|lighthouse|pagespeed|preview|facebookexternalhit|
           embedly|python|curl|wget|httpclient|java\/|go-http|okhttp|axios|node-fetch|undici|scrapy|-user\b/xi

    BROWSERS = [
      [ /Instagram/, "Instagram" ], [ /FBAN|FBAV/, "Facebook" ], [ /LinkedInApp/, "LinkedIn" ],
      [ /Edg(e|A|iOS)?\//, "Edge" ], [ /OPR\/|Opera/, "Opera" ], [ /SamsungBrowser/, "Samsung Internet" ],
      [ /Firefox\/|FxiOS/, "Firefox" ], [ /Chrome\/|CriOS/, "Chrome" ], [ /Version\/[\d.]+.*Safari/, "Safari" ]
    ].freeze

    SYSTEMS = [
      [ /iPhone|iPad|iPod/, "iOS" ], [ /Android/, "Android" ], [ /CrOS/, "ChromeOS" ], [ /Windows/, "Windows" ],
      [ /Macintosh|Mac OS X/, "macOS" ], [ /Linux/, "Linux" ]
    ].freeze

    def initialize(user_agent, screen_width: nil)
      @ua = user_agent.to_s
      @width = screen_width.to_i if screen_width.present?
    end

    def bot?
      @ua.blank? || @ua.match?(BOT)
    end

    # Pela largura da tela; sem ela, pelo user agent.
    def device_type
      if @width&.positive?
        return "mobile" if @width < 768
        return "tablet" if @width < 1024

        "desktop"
      elsif @ua.match?(/iPad|Tablet/i) || (@ua.include?("Android") && !@ua.include?("Mobile"))
        "tablet"
      elsif @ua.match?(/Mobi|iPhone|Android/)
        "mobile"
      else
        "desktop"
      end
    end

    def browser = match(BROWSERS)
    def os = match(SYSTEMS)

    private

    def match(table)
      table.find { |pattern, _| @ua.match?(pattern) }&.last || "Outro"
    end
  end
end
