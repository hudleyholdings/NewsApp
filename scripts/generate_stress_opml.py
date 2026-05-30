#!/usr/bin/env python3
"""Generate a ~1000-feed OPML file for stress-testing NewsApp.

Mixes:
- ~200 curated real RSS feeds (news, tech, science, sports, finance, culture)
- ~800 subreddit feeds templated as https://www.reddit.com/r/<name>/.rss

Run: python3 scripts/generate_stress_opml.py
Output: ~/Desktop/newsapp-1k-stress-feeds.opml
"""

import os
import html

# ---------------------------------------------------------------------------
# Curated real RSS feeds, grouped for OPML categories.
# ---------------------------------------------------------------------------

CURATED = {
    "News - World": [
        ("BBC News - World", "https://feeds.bbci.co.uk/news/world/rss.xml", "https://www.bbc.com/news/world"),
        ("BBC News - Top Stories", "https://feeds.bbci.co.uk/news/rss.xml", "https://www.bbc.com/news"),
        ("BBC News - UK", "https://feeds.bbci.co.uk/news/uk/rss.xml", "https://www.bbc.com/news/uk"),
        ("BBC News - Europe", "https://feeds.bbci.co.uk/news/world/europe/rss.xml", "https://www.bbc.com/news/world/europe"),
        ("BBC News - Asia", "https://feeds.bbci.co.uk/news/world/asia/rss.xml", "https://www.bbc.com/news/world/asia"),
        ("BBC News - Africa", "https://feeds.bbci.co.uk/news/world/africa/rss.xml", "https://www.bbc.com/news/world/africa"),
        ("BBC News - Latin America", "https://feeds.bbci.co.uk/news/world/latin_america/rss.xml", "https://www.bbc.com/news/world/latin_america"),
        ("BBC News - Middle East", "https://feeds.bbci.co.uk/news/world/middle_east/rss.xml", "https://www.bbc.com/news/world/middle_east"),
        ("NYT - World", "https://rss.nytimes.com/services/xml/rss/nyt/World.xml", "https://www.nytimes.com/section/world"),
        ("NYT - Africa", "https://rss.nytimes.com/services/xml/rss/nyt/Africa.xml", "https://www.nytimes.com/section/world/africa"),
        ("NYT - Americas", "https://rss.nytimes.com/services/xml/rss/nyt/Americas.xml", "https://www.nytimes.com/section/world/americas"),
        ("NYT - Asia Pacific", "https://rss.nytimes.com/services/xml/rss/nyt/AsiaPacific.xml", "https://www.nytimes.com/section/world/asia"),
        ("NYT - Europe", "https://rss.nytimes.com/services/xml/rss/nyt/Europe.xml", "https://www.nytimes.com/section/world/europe"),
        ("NYT - Middle East", "https://rss.nytimes.com/services/xml/rss/nyt/MiddleEast.xml", "https://www.nytimes.com/section/world/middleeast"),
        ("Guardian - World", "https://www.theguardian.com/world/rss", "https://www.theguardian.com/world"),
        ("Guardian - International", "https://www.theguardian.com/international/rss", "https://www.theguardian.com/international"),
        ("Reuters - World", "https://feeds.reuters.com/Reuters/worldNews", "https://www.reuters.com/world"),
        ("AP News - Top", "https://feeds.apnews.com/rss/apf-topnews", "https://apnews.com"),
        ("AP News - World", "https://feeds.apnews.com/rss/apf-intlnews", "https://apnews.com/hub/world-news"),
        ("Al Jazeera English", "https://www.aljazeera.com/xml/rss/all.xml", "https://www.aljazeera.com"),
        ("Deutsche Welle - World", "https://rss.dw.com/rdf/rss-en-all", "https://www.dw.com/en/top-stories/s-9097"),
        ("France 24 - World", "https://www.france24.com/en/rss", "https://www.france24.com/en/"),
        ("NPR - World", "https://feeds.npr.org/1004/rss.xml", "https://www.npr.org/sections/world"),
        ("ABC News - International", "https://abcnews.go.com/abcnews/internationalheadlines", "https://abcnews.go.com/International"),
        ("CBS News - World", "https://www.cbsnews.com/latest/rss/world", "https://www.cbsnews.com/world"),
        ("NBC News - World", "https://feeds.nbcnews.com/nbcnews/public/world", "https://www.nbcnews.com/world"),
        ("PBS NewsHour - World", "https://www.pbs.org/newshour/feeds/rss/world", "https://www.pbs.org/newshour/world"),
        ("CNN - World", "http://rss.cnn.com/rss/edition_world.rss", "https://www.cnn.com/world"),
        ("Yahoo News - World", "https://www.yahoo.com/news/world/rss", "https://www.yahoo.com/news/world"),
        ("Sky News - World", "https://feeds.skynews.com/feeds/rss/world.xml", "https://news.sky.com/world"),
        ("Times of Israel - World", "https://www.timesofisrael.com/feed/", "https://www.timesofisrael.com"),
        ("Japan Times - World", "https://www.japantimes.co.jp/news/feed/", "https://www.japantimes.co.jp"),
        ("Korea Herald", "http://www.koreaherald.com/common/rss_xml.php?ct=102", "http://www.koreaherald.com"),
        ("South China Morning Post", "https://www.scmp.com/rss/91/feed", "https://www.scmp.com"),
        ("Times of India - World", "https://timesofindia.indiatimes.com/rssfeeds/296589292.cms", "https://timesofindia.indiatimes.com/world"),
        ("Hindustan Times - World", "https://www.hindustantimes.com/feeds/rss/world-news/rssfeed.xml", "https://www.hindustantimes.com/world-news"),
    ],
    "News - US": [
        ("NYT - U.S.", "https://rss.nytimes.com/services/xml/rss/nyt/US.xml", "https://www.nytimes.com/section/us"),
        ("NYT - Politics", "https://rss.nytimes.com/services/xml/rss/nyt/Politics.xml", "https://www.nytimes.com/section/politics"),
        ("NYT - Upshot", "https://rss.nytimes.com/services/xml/rss/nyt/Upshot.xml", "https://www.nytimes.com/section/upshot"),
        ("Washington Post - National", "https://feeds.washingtonpost.com/rss/national", "https://www.washingtonpost.com"),
        ("Washington Post - Politics", "https://feeds.washingtonpost.com/rss/politics", "https://www.washingtonpost.com/politics"),
        ("LA Times - California", "https://www.latimes.com/california/rss2.0.xml", "https://www.latimes.com/california"),
        ("USA Today - News", "https://rssfeeds.usatoday.com/usatoday-NewsTopStories", "https://www.usatoday.com/news"),
        ("Politico", "https://www.politico.com/rss/politicopicks.xml", "https://www.politico.com"),
        ("The Hill", "https://thehill.com/feed/", "https://thehill.com"),
        ("ProPublica", "https://www.propublica.org/feeds/propublica/main", "https://www.propublica.org"),
        ("NPR - National", "https://feeds.npr.org/1003/rss.xml", "https://www.npr.org/sections/national"),
        ("NPR - Politics", "https://feeds.npr.org/1014/rss.xml", "https://www.npr.org/sections/politics"),
        ("CBS News - U.S.", "https://www.cbsnews.com/latest/rss/us", "https://www.cbsnews.com/us"),
        ("NBC News - U.S.", "https://feeds.nbcnews.com/nbcnews/public/news", "https://www.nbcnews.com/us-news"),
        ("ABC News - Top", "https://abcnews.go.com/abcnews/topstories", "https://abcnews.go.com"),
        ("Fox News - Politics", "https://moxie.foxnews.com/google-publisher/politics.xml", "https://www.foxnews.com/politics"),
        ("Drudge Report", "https://feeds.feedburner.com/DrudgeReportFeed", "https://drudgereport.com"),
        ("Reason", "https://reason.com/feed/", "https://reason.com"),
        ("National Review", "https://www.nationalreview.com/feed/", "https://www.nationalreview.com"),
        ("Vox", "https://www.vox.com/rss/index.xml", "https://www.vox.com"),
        ("The Atlantic", "https://www.theatlantic.com/feed/all/", "https://www.theatlantic.com"),
        ("New Yorker", "https://www.newyorker.com/feed/everything", "https://www.newyorker.com"),
        ("Slate", "https://slate.com/feeds/all.rss", "https://slate.com"),
        ("Mother Jones", "https://www.motherjones.com/feed/", "https://www.motherjones.com"),
        ("The Intercept", "https://theintercept.com/feed/?lang=en", "https://theintercept.com"),
        ("Axios", "https://api.axios.com/feed/", "https://www.axios.com"),
        ("Semafor", "https://www.semafor.com/feed.xml", "https://www.semafor.com"),
        ("Defector", "https://defector.com/feed", "https://defector.com"),
    ],
    "Business & Finance": [
        ("CNBC - Top News", "https://www.cnbc.com/id/100003114/device/rss/rss.html", "https://www.cnbc.com"),
        ("CNBC - Business", "https://www.cnbc.com/id/10001147/device/rss/rss.html", "https://www.cnbc.com/business"),
        ("CNBC - Markets", "https://www.cnbc.com/id/15839069/device/rss/rss.html", "https://www.cnbc.com/markets"),
        ("CNBC - Tech", "https://www.cnbc.com/id/19854910/device/rss/rss.html", "https://www.cnbc.com/technology"),
        ("MarketWatch - Top Stories", "https://feeds.content.dowjones.io/public/rss/mw_topstories", "https://www.marketwatch.com"),
        ("Wall Street Journal - World", "https://feeds.content.dowjones.io/public/rss/RSSWorldNews", "https://www.wsj.com"),
        ("Wall Street Journal - Markets", "https://feeds.content.dowjones.io/public/rss/RSSMarketsMain", "https://www.wsj.com/news/markets"),
        ("Financial Times - World", "https://www.ft.com/world?format=rss", "https://www.ft.com/world"),
        ("Financial Times - Companies", "https://www.ft.com/companies?format=rss", "https://www.ft.com/companies"),
        ("Bloomberg - Top", "https://feeds.bloomberg.com/markets/news.rss", "https://www.bloomberg.com/markets"),
        ("Bloomberg - Politics", "https://feeds.bloomberg.com/politics/news.rss", "https://www.bloomberg.com/politics"),
        ("Bloomberg - Technology", "https://feeds.bloomberg.com/technology/news.rss", "https://www.bloomberg.com/technology"),
        ("Yahoo Finance", "https://finance.yahoo.com/news/rssindex", "https://finance.yahoo.com"),
        ("The Motley Fool", "https://www.fool.com/feeds/index.aspx", "https://www.fool.com"),
        ("Seeking Alpha", "https://seekingalpha.com/feed.xml", "https://seekingalpha.com"),
        ("Forbes", "https://www.forbes.com/real-time/feed2/", "https://www.forbes.com"),
        ("Business Insider", "https://www.businessinsider.com/rss", "https://www.businessinsider.com"),
        ("Quartz", "https://qz.com/feed/", "https://qz.com"),
        ("The Economist - Business", "https://www.economist.com/business/rss.xml", "https://www.economist.com/business"),
        ("The Economist - Finance & Economics", "https://www.economist.com/finance-and-economics/rss.xml", "https://www.economist.com/finance-and-economics"),
        ("Calculated Risk", "https://www.calculatedriskblog.com/feeds/posts/default", "https://www.calculatedriskblog.com"),
        ("Marginal Revolution", "https://marginalrevolution.com/feed", "https://marginalrevolution.com"),
        ("Naked Capitalism", "https://www.nakedcapitalism.com/feed", "https://www.nakedcapitalism.com"),
        ("Zero Hedge", "https://feeds.feedburner.com/zerohedge/feed", "https://www.zerohedge.com"),
        ("Stratechery", "https://stratechery.com/feed/", "https://stratechery.com"),
        ("Matt Levine - Money Stuff", "https://www.bloomberg.com/opinion/authors/ARbTQlRLRjE/matthew-s-levine.rss", "https://www.bloomberg.com/opinion/columnists/matthew-levine"),
        ("Pragmatic Capitalism", "https://www.pragcap.com/feed/", "https://www.pragcap.com"),
    ],
    "Technology": [
        ("Hacker News - Front Page", "https://hnrss.org/frontpage", "https://news.ycombinator.com"),
        ("Hacker News - Newest", "https://hnrss.org/newest", "https://news.ycombinator.com/newest"),
        ("Hacker News - Best", "https://hnrss.org/best", "https://news.ycombinator.com/best"),
        ("Hacker News - Show", "https://hnrss.org/show", "https://news.ycombinator.com/show"),
        ("Hacker News - Ask", "https://hnrss.org/ask", "https://news.ycombinator.com/ask"),
        ("Lobsters", "https://lobste.rs/rss", "https://lobste.rs"),
        ("Slashdot", "http://rss.slashdot.org/Slashdot/slashdotMain", "https://slashdot.org"),
        ("Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "https://arstechnica.com"),
        ("Ars Technica - Apple", "https://feeds.arstechnica.com/arstechnica/apple", "https://arstechnica.com/gadgets/apple"),
        ("Ars Technica - Gaming", "https://feeds.arstechnica.com/arstechnica/gaming", "https://arstechnica.com/gaming"),
        ("Ars Technica - Tech Policy", "https://feeds.arstechnica.com/arstechnica/tech-policy", "https://arstechnica.com/tech-policy"),
        ("The Verge", "https://www.theverge.com/rss/index.xml", "https://www.theverge.com"),
        ("The Verge - Tech", "https://www.theverge.com/tech/rss/index.xml", "https://www.theverge.com/tech"),
        ("TechCrunch", "https://techcrunch.com/feed/", "https://techcrunch.com"),
        ("TechCrunch - Startups", "https://techcrunch.com/startups/feed/", "https://techcrunch.com/startups"),
        ("Wired", "https://www.wired.com/feed/rss", "https://www.wired.com"),
        ("Wired - Business", "https://www.wired.com/feed/category/business/latest/rss", "https://www.wired.com/category/business"),
        ("Wired - Security", "https://www.wired.com/feed/category/security/latest/rss", "https://www.wired.com/category/security"),
        ("Wired - Gear", "https://www.wired.com/feed/category/gear/latest/rss", "https://www.wired.com/category/gear"),
        ("Engadget", "https://www.engadget.com/rss.xml", "https://www.engadget.com"),
        ("Gizmodo", "https://gizmodo.com/rss", "https://gizmodo.com"),
        ("9to5Mac", "https://9to5mac.com/feed/", "https://9to5mac.com"),
        ("9to5Google", "https://9to5google.com/feed/", "https://9to5google.com"),
        ("MacRumors", "https://feeds.macrumors.com/MacRumors-All", "https://www.macrumors.com"),
        ("AppleInsider", "https://appleinsider.com/rss/news", "https://appleinsider.com"),
        ("Daring Fireball", "https://daringfireball.net/feeds/main", "https://daringfireball.net"),
        ("Six Colors", "https://sixcolors.com/feed/", "https://sixcolors.com"),
        ("MacStories", "https://www.macstories.net/feed/", "https://www.macstories.net"),
        ("The Information - Public", "https://www.theinformation.com/feed", "https://www.theinformation.com"),
        ("Anandtech", "https://www.anandtech.com/rss/", "https://www.anandtech.com"),
        ("Tom's Hardware", "https://www.tomshardware.com/feeds.xml", "https://www.tomshardware.com"),
        ("Hackaday", "https://hackaday.com/blog/feed/", "https://hackaday.com"),
        ("Phoronix", "https://www.phoronix.com/rss.php", "https://www.phoronix.com"),
        ("LWN.net", "https://lwn.net/headlines/rss", "https://lwn.net"),
        ("dev.to", "https://dev.to/feed/", "https://dev.to"),
        ("CSS-Tricks", "https://css-tricks.com/feed/", "https://css-tricks.com"),
        ("Smashing Magazine", "https://www.smashingmagazine.com/feed/", "https://www.smashingmagazine.com"),
        ("Krebs on Security", "https://krebsonsecurity.com/feed/", "https://krebsonsecurity.com"),
        ("Schneier on Security", "https://www.schneier.com/feed/atom/", "https://www.schneier.com"),
        ("Bleeping Computer", "https://www.bleepingcomputer.com/feed/", "https://www.bleepingcomputer.com"),
        ("The Register", "https://www.theregister.com/headlines.atom", "https://www.theregister.com"),
        ("ZDNet", "https://www.zdnet.com/news/rss.xml", "https://www.zdnet.com"),
        ("OMG! Ubuntu!", "https://www.omgubuntu.co.uk/feed", "https://www.omgubuntu.co.uk"),
        ("OSnews", "https://www.osnews.com/feed/", "https://www.osnews.com"),
        ("Restofworld", "https://restofworld.org/feed/latest/", "https://restofworld.org"),
        ("404 Media", "https://www.404media.co/rss/", "https://www.404media.co"),
        ("Pivot to AI", "https://pivot-to-ai.com/feed/", "https://pivot-to-ai.com"),
        ("Simon Willison", "https://simonwillison.net/atom/everything/", "https://simonwillison.net"),
        ("Anthropic - News", "https://www.anthropic.com/news/rss.xml", "https://www.anthropic.com/news"),
        ("OpenAI Blog", "https://openai.com/blog/rss.xml", "https://openai.com/blog"),
        ("Google AI Blog", "https://blog.google/technology/ai/rss/", "https://blog.google/technology/ai/"),
        ("DeepMind Blog", "https://deepmind.google/blog/rss.xml", "https://deepmind.google/blog/"),
        ("MIT Tech Review", "https://www.technologyreview.com/feed/", "https://www.technologyreview.com"),
    ],
    "Science": [
        ("Nature - News", "https://www.nature.com/nature.rss", "https://www.nature.com"),
        ("Science - News", "https://www.science.org/rss/news_current.xml", "https://www.science.org/news"),
        ("New Scientist", "https://www.newscientist.com/feed/home/", "https://www.newscientist.com"),
        ("Scientific American", "https://rss.sciam.com/ScientificAmerican-Global", "https://www.scientificamerican.com"),
        ("Quanta Magazine", "https://www.quantamagazine.org/feed/", "https://www.quantamagazine.org"),
        ("Phys.org", "https://phys.org/rss-feed/", "https://phys.org"),
        ("Science Daily", "https://www.sciencedaily.com/rss/all.xml", "https://www.sciencedaily.com"),
        ("Eos", "https://eos.org/feed", "https://eos.org"),
        ("Nautilus", "https://nautil.us/feed", "https://nautil.us"),
        ("NASA Breaking News", "https://www.nasa.gov/news-release/feed/", "https://www.nasa.gov/news"),
        ("Astronomy.com", "https://astronomy.com/feed", "https://astronomy.com"),
        ("Space.com", "https://www.space.com/feeds/all", "https://www.space.com"),
        ("Sky & Telescope", "https://skyandtelescope.org/feed/", "https://skyandtelescope.org"),
        ("APOD", "https://apod.nasa.gov/apod.rss", "https://apod.nasa.gov/apod/"),
    ],
    "Sports": [
        ("ESPN - Top News", "https://www.espn.com/espn/rss/news", "https://www.espn.com"),
        ("ESPN - NFL", "https://www.espn.com/espn/rss/nfl/news", "https://www.espn.com/nfl"),
        ("ESPN - NBA", "https://www.espn.com/espn/rss/nba/news", "https://www.espn.com/nba"),
        ("ESPN - MLB", "https://www.espn.com/espn/rss/mlb/news", "https://www.espn.com/mlb"),
        ("ESPN - NHL", "https://www.espn.com/espn/rss/nhl/news", "https://www.espn.com/nhl"),
        ("ESPN - College Football", "https://www.espn.com/espn/rss/ncf/news", "https://www.espn.com/college-football"),
        ("ESPN - College Basketball", "https://www.espn.com/espn/rss/ncb/news", "https://www.espn.com/mens-college-basketball"),
        ("ESPN - Soccer", "https://www.espn.com/espn/rss/soccer/news", "https://www.espn.com/soccer"),
        ("ESPN - Tennis", "https://www.espn.com/espn/rss/tennis/news", "https://www.espn.com/tennis"),
        ("ESPN - Golf", "https://www.espn.com/espn/rss/golf/news", "https://www.espn.com/golf"),
        ("BBC Sport - Top", "https://feeds.bbci.co.uk/sport/rss.xml", "https://www.bbc.com/sport"),
        ("BBC Sport - Football", "https://feeds.bbci.co.uk/sport/football/rss.xml", "https://www.bbc.com/sport/football"),
        ("BBC Sport - Cricket", "https://feeds.bbci.co.uk/sport/cricket/rss.xml", "https://www.bbc.com/sport/cricket"),
        ("BBC Sport - Rugby Union", "https://feeds.bbci.co.uk/sport/rugby-union/rss.xml", "https://www.bbc.com/sport/rugby-union"),
        ("BBC Sport - Formula 1", "https://feeds.bbci.co.uk/sport/formula1/rss.xml", "https://www.bbc.com/sport/formula1"),
        ("BBC Sport - Tennis", "https://feeds.bbci.co.uk/sport/tennis/rss.xml", "https://www.bbc.com/sport/tennis"),
        ("BBC Sport - Boxing", "https://feeds.bbci.co.uk/sport/boxing/rss.xml", "https://www.bbc.com/sport/boxing"),
        ("Bleacher Report", "https://syndication.bleacherreport.com/amp/articles/featured.rss", "https://bleacherreport.com"),
        ("The Athletic", "https://theathletic.com/rss-feed/", "https://theathletic.com"),
        ("Sports Illustrated", "https://www.si.com/.rss/full/", "https://www.si.com"),
        ("CBS Sports", "https://www.cbssports.com/rss/headlines/", "https://www.cbssports.com"),
        ("Yahoo Sports", "https://sports.yahoo.com/rss/", "https://sports.yahoo.com"),
        ("NFL.com - News", "https://www.nfl.com/rss/rsslanding?searchString=home", "https://www.nfl.com"),
        ("Deadspin", "https://deadspin.com/rss", "https://deadspin.com"),
    ],
    "Culture": [
        ("Rolling Stone - Music", "https://www.rollingstone.com/music/feed/", "https://www.rollingstone.com/music"),
        ("Rolling Stone - Movies", "https://www.rollingstone.com/movies/feed/", "https://www.rollingstone.com/movies"),
        ("Rolling Stone - TV", "https://www.rollingstone.com/tv/feed/", "https://www.rollingstone.com/tv"),
        ("Pitchfork", "https://pitchfork.com/rss/news/", "https://pitchfork.com"),
        ("Variety", "https://variety.com/feed/", "https://variety.com"),
        ("Hollywood Reporter", "https://www.hollywoodreporter.com/feed/", "https://www.hollywoodreporter.com"),
        ("Deadline", "https://deadline.com/feed/", "https://deadline.com"),
        ("Vulture", "https://www.vulture.com/rss/index.xml", "https://www.vulture.com"),
        ("IndieWire", "https://www.indiewire.com/feed/", "https://www.indiewire.com"),
        ("AV Club", "https://www.avclub.com/rss", "https://www.avclub.com"),
        ("Polygon", "https://www.polygon.com/rss/index.xml", "https://www.polygon.com"),
        ("Kotaku", "https://kotaku.com/rss", "https://kotaku.com"),
        ("IGN - All", "https://feeds.ign.com/ign/all", "https://www.ign.com"),
        ("GameSpot - News", "https://www.gamespot.com/feeds/news/", "https://www.gamespot.com"),
        ("Eurogamer", "https://www.eurogamer.net/?format=rss", "https://www.eurogamer.net"),
        ("PC Gamer", "https://www.pcgamer.com/rss/", "https://www.pcgamer.com"),
        ("NPR - Music", "https://feeds.npr.org/1039/rss.xml", "https://www.npr.org/sections/music"),
        ("NPR - Arts & Life", "https://feeds.npr.org/1008/rss.xml", "https://www.npr.org/sections/arts-and-life"),
        ("Stereogum", "https://www.stereogum.com/feed/", "https://www.stereogum.com"),
        ("Consequence", "https://consequence.net/feed/", "https://consequence.net"),
        ("LitHub", "https://lithub.com/feed/", "https://lithub.com"),
        ("Paris Review - Blog", "https://www.theparisreview.org/blog/feed/", "https://www.theparisreview.org/blog"),
        ("The Cut", "https://www.thecut.com/rss/index.xml", "https://www.thecut.com"),
    ],
    "Comics & Webcomics": [
        ("xkcd", "https://xkcd.com/rss.xml", "https://xkcd.com"),
        ("SMBC", "https://www.smbc-comics.com/comic/rss", "https://www.smbc-comics.com"),
        ("Questionable Content", "https://questionablecontent.net/QCRSS.xml", "https://questionablecontent.net"),
        ("Penny Arcade", "https://www.penny-arcade.com/feed", "https://www.penny-arcade.com"),
        ("The Oatmeal", "https://theoatmeal.com/feed/rss", "https://theoatmeal.com"),
    ],
}

# ---------------------------------------------------------------------------
# YouTube channels — (display name, channel ID). Channel RSS is reliable at
# https://www.youtube.com/feeds/videos.xml?channel_id=<ID>
# ---------------------------------------------------------------------------

YOUTUBE_CHANNELS = [
    ("MKBHD", "UCBJycsmduvYEL83R_U4JriQ"),
    ("Linus Tech Tips", "UCXuqSBlHAE6Xw-yeJA0Tunw"),
    ("Marques Brownlee Waveform", "UCS9Tx3MEt_iWEpYpKnHGI8w"),
    ("Veritasium", "UCHnyfMqiRRG1u-2MsSQLbXA"),
    ("Vsauce", "UC6nSFpj9HTCZ5t-N3Rm3-HA"),
    ("Vsauce2", "UCqmugCqELzhIMNYnsjScXXw"),
    ("Vsauce3", "UCUyDOdBWhC1MCxEjC46d-zw"),
    ("Tom Scott", "UCBa659QWEk1AI4Tg--mrJ2A"),
    ("Mark Rober", "UCY1kMZp36IQSyNx_9h4mpCg"),
    ("Kurzgesagt", "UCsXVk37bltHxD1rDPwtNM8Q"),
    ("Computerphile", "UC9-y-6csu5WGm29I7JiwpnA"),
    ("Numberphile", "UCoxcjq-8xIDTYp3uz647V5A"),
    ("3Blue1Brown", "UCYO_jab_esuFRV4b17AJtAw"),
    ("AsapSCIENCE", "UCC552Sd-3nyi_tk2BudLUzA"),
    ("TED-Ed", "UCsooa4yRKGN_zEE8iknghZA"),
    ("The Coding Train", "UCvjgXvBlbQiydffZU7m1_aw"),
    ("ColdFusion", "UC4QZ_LsYcvcq7qOsOhpAX4A"),
    ("LegalEagle", "UCpa-Zb0ZcQjTCPP1Dx_1M8Q"),
    ("Wendover Productions", "UC9RM-iSvTu1uPJb8X5yp3EQ"),
    ("Real Engineering", "UCR1IuLEqb6UEA_zQ81kwXfg"),
    ("Practical Engineering", "UCMOqf8ab-42UUQIdVoKwjlQ"),
    ("SmarterEveryDay", "UC6107grRI4m0o2-emgoDnAA"),
    ("Two Minute Papers", "UCbfYPyITQ-7l4upoX8nvctg"),
    ("Fireship", "UCsBjURrPoezykLs9EqgamOA"),
    ("Computer History Museum", "UC0WiM4VktvjEAaHkSrwzZNw"),
    ("Crash Course", "UCX6b17PVsYBQ0ip5gyeme-Q"),
    ("SciShow", "UCZYTClx2T1of7BRZ86-8fow"),
    ("SciShow Space", "UCrMePiHCWG4Vwqv3t7W9EFg"),
    ("MinutePhysics", "UCUHW94eEFW7hkUMVaZz4eDg"),
    ("MinuteEarth", "UCeiYXex_fwgYDonaTcSIk6w"),
    ("PBS Space Time", "UC7_gcs09iThXybpVgjHZ_7g"),
    ("PBS Eons", "UCzR-rom72PHN9Zg7RML9EbA"),
    ("CGP Grey", "UC2C_jShtL725hvbm1arSV9w"),
    ("Brady Haran (Sixty Symbols)", "UCvBqzzvUBLCs8Y7Axb-jZew"),
    ("Mathologer", "UCN5lvw3KevtbqyN1ULsl_8Q"),
    ("Stand-up Maths", "UCSju5G2aFaWMqn-_0YBtq5A"),
    ("Smarter Every Day 2", "UC4lJlR_jcKa45GjLDD3FFwg"),
    ("Engineer Guy", "UC2bkHVIDjXS7sgrgjFtzOXQ"),
    ("Tested", "UCiDJtJKMICpb9B1qf7qjEOA"),
    ("LinusTechTips Shorts (TechLinked)", "UCeeFfhMcJa1kjtfZAGskOCA"),
    ("Short Circuit", "UCdBK94H6oZT2Q7l0-b0xmMg"),
    ("ShortCircuit", "UCdBK94H6oZT2Q7l0-b0xmMg"),
    ("Linus Sebastian", "UCxQbYGpbdrh-b2ND-AfIybg"),
    ("Dave2D", "UCVYamHliCI9rw1tHR1xbkfw"),
    ("JerryRigEverything", "UCu0eYWdJ45R1f3Y8tDpktow"),
    ("UrAvgConsumer", "UCwn5Rs_VRBuXTwwhMSb7y1Q"),
    ("Casey Neistat", "UCtinbF-Q-fVthA0qrFQTgXQ"),
    ("Peter McKinnon", "UC3DkFux8Iv-aYnTRWzwaiBA"),
    ("Mango Street", "UCWWFiK_QGRpQfQrIfgsRYsg"),
    ("Daniel Schiffer", "UCh0Lah_KVKKnGRiX5MtVnEQ"),
    ("Defunctland", "UClFbb1ouXVZzjMB9Yha5nAQ"),
    ("LGR", "UCLx053rWZxCiYWsBETgdKrQ"),
    ("Techmoan", "UC5I2hjZYiW9gZPVkvzM8_Cw"),
    ("Big Clive", "UCtM5z2gkrGRuWd0JQMx76qA"),
    ("AvE", "UCpHTAE2EOwWv1SVhWUMOQrA"),
    ("This Old Tony", "UC5NO8MgTQKHAWXp6z8Xl7yQ"),
    ("Adam Savage's Tested", "UCiDJtJKMICpb9B1qf7qjEOA"),
    ("Stuff Made Here", "UCj1VqrHhDte54oLgPG4xpuQ"),
    ("Allec Joshua Ibay", "UCC3qy_DyqsQqp7iE7TWMVwQ"),
    ("Steve Mould", "UCEIwxahdLz7bap-VDs9h35A"),
    ("Action Lab", "UC1VLQPn9cYhy3oOliw_lhmQ"),
    ("Backyard Scientist", "UC06E4Y_-ybJgBUMtXx8uNNw"),
    ("Slow Mo Guys", "UCUK0HBIBWgM2c4vsPhkYY4w"),
    ("Smarter Every Day 2", "UCfYNI4lY_lr-vbtPodNlBLA"),
    ("Half as Interesting", "UCuCkxoKLYO_EQ2GeFtbM_bw"),
    ("HAI", "UCuCkxoKLYO_EQ2GeFtbM_bw"),
    ("RealLifeLore", "UCP5tjEmvPItGyLhmjdwP7Ww"),
    ("Geography Now", "UC0FAjW2QmGTbThfEpjPdolg"),
    ("OverSimplified", "UCNIuvl7V8zACPpTmmNIqP2A"),
    ("Extra History", "UCCODtTcd5M1JavPCOr_Uydg"),
    ("The Infographics Show", "UCfdNM3NAhaBOXCafH7krzrA"),
    ("In a Nutshell - Kurzgesagt", "UCsXVk37bltHxD1rDPwtNM8Q"),
    ("Polyphonic", "UCT5SsmoEhRPsv5kgFjeQ8Ow"),
    ("12tone", "UCTUtqcDkzw7bisadh6AOx5w"),
    ("Adam Neely", "UCnkp4xDOwqqJD7sSM3xdUiQ"),
    ("Rick Beato", "UCJquYOG5EL82sKTfH9aMA9Q"),
    ("Polyphia", "UCKBO9C8tF6_8L_eqovZBzTw"),
    ("ChilledCow / Lofi Girl", "UCSJ4gkVC6NrvII8umztf0Ow"),
    ("NPR Music", "UC4eYXhJI4-7wSWc8UNRwD4A"),
    ("KEXP", "UC4Bf63KZxa7H1WAm4tCx2lA"),
    ("CinemaWins", "UCL5kBJmBUVFLYBDiSiK1VDw"),
    ("CinemaSins", "UCYUQQgogVeQY8cMQamhHJcg"),
    ("Lessons from the Screenplay", "UCErSSa3CaP_GJxmFpdjG9Jw"),
    ("Every Frame a Painting", "UCjFqcJQXGZ6T6sxyFB-5i6A"),
    ("StoryBrain", "UCHvqGSF_LD3i7Z9MoifP_lA"),
    ("kaptainkristian", "UCG8bDPqJSjjkkF9q-MgFTuw"),
    ("Patrick (H) Willems", "UCXSYpvxnyT9Q1g8WyMTrxJg"),
    ("Just Write", "UCs9-jVUlolnEgyA9wfg3rgQ"),
    ("LinusTechTips - Mac Address", "UC0NCbj8CxzeCGIF6sODJ-7A"),
    ("Hbomberguy", "UClt01z1wHHT7c5lKcU8pxRQ"),
    ("Folding Ideas", "UCyNtlmLB73-7gtlBz00XOQQ"),
    ("Lindsay Ellis", "UCG1h-Wqjtwz7uUANw6gazRw"),
    ("Contrapoints", "UCNvsIonJdJ5E4EXMa65VYpA"),
    ("Philosophy Tube", "UC2PA-AKmVpU6NKCGtZq_rKQ"),
    ("Wisecrack", "UC6-ymYjG0SU0jUWnWh9ZzEQ"),
    ("Renegade Cut", "UCKwGSxyfwOMqsZN6FJExBzg"),
    ("Captain Disillusion", "UCEOXxzW2vU0P-0THehuIIeg"),
    ("Daniel Thrasher", "UCNb_RIE7nNohSwSWqRX2OEw"),
    ("Marques on iPad", "UCFAiFyGs6oDiF1Nf-rRJpZA"),
    ("Boston Dynamics", "UC7vVhkEfw4nOGp8TyDk7RcQ"),
    ("OpenAI", "UCXZCJLdBC09xxGZ6gcdrc6A"),
    ("Anthropic", "UCrDwWp7EBBv4NwvScIpBDOA"),
    ("DeepLearningAI", "UCcIXc5mJsHVYTZR1maL5l9w"),
    ("Two Minute Papers", "UCbfYPyITQ-7l4upoX8nvctg"),
    ("Yannic Kilcher", "UCZHmQk67mSJgfCCTn7xBfew"),
    ("Lex Fridman", "UCSHZKyawb77ixDdsGog4iWA"),
    ("All-In Podcast", "UCESLZhusAkFfsNsApnjF_Cg"),
    ("Joe Rogan Experience", "UCzQUP1qoWDoEbmsQxvdjxgQ"),
    ("Theo Von", "UC5AQEUAwCh1sGDvkQtkDWUQ"),
    ("Andrew Huberman", "UC2D2CMWXMOVWx7giW1n3LIg"),
    ("Smarter Every Day Math", "UCgazx8jMb1JcXLwIB7r2wzg"),
    ("Mike Boyd", "UCIRiWCPZoUyZDbydIqitHtQ"),
    ("Beard Meets Food", "UCQRD5_5wTd3LBUMQfm2ZB3g"),
    ("Internet Historian", "UCR1D15p_vdP3HkrH8wgjQRw"),
    ("Sam O'Nella Academy", "UC1DTYW241WD64ah5BFWn4JA"),
    ("Bill Wurtz", "UCq6aw03lNILzV96UvEAASfQ"),
    ("Tom Stanton", "UC67gfx2Fg7K2NSHqoENVgwA"),
    ("Strange Parts", "UCO8DQrSp5yEP937qNqTooOw"),
    ("Naomi Wu Sexy Cyborg", "UC4Otr-AraMOFYbTfsHbcXFA"),
    ("Cleo Abram", "UCywSXMTjYAxClK4uZD-_kRA"),
    ("Johnny Harris", "UCfRZsRgZkUjcgkVA5GJlhYg"),
    ("Vox", "UCLXo7UDZvByw2ixzpQCufnA"),
    ("Bloomberg Originals", "UCUMZ7gohGI9HcU9VNsr2FJQ"),
    ("Bloomberg Television", "UCIALMKvObZNtJ6AmdCLP7Lg"),
    ("CNBC", "UCrp_UI8XtuYfpiqluWLD7Lw"),
    ("CNBC Television", "UCvJJ_dzjViJCoLf5uKUTwoA"),
    ("Wall Street Journal", "UCK7tptUDHh-RYDsdxO1-5QQ"),
    ("Financial Times", "UCmuAghIxIuVlqEMixVdz_Jg"),
    ("The Economist", "UC0p5jTq6Xx_DosDFxVXnWaQ"),
    ("BBC News", "UC16niRr50-MSBwiO3YDb3RA"),
    ("CNN", "UCupvZG-5ko_eiXAupbDfxWw"),
    ("Sky News", "UCoMdktPbSTixAyNGwb-UYkQ"),
    ("Al Jazeera English", "UCNye-wNBqNL5ZzHSJj3l8Bg"),
    ("DW News", "UCknLrEdhRCp1aegoMqRaCZg"),
    ("PBS NewsHour", "UC6ZFN9Tx6xh-skXCuRHCDpQ"),
    ("60 Minutes", "UCK7QFhEU1mLDXoFV9DZh3UA"),
    ("Vice News", "UCZaT_X_mc0BI-djXOlfhqWQ"),
    ("NowThis News", "UC8-Th83bH_thdKZDJCrn88g"),
    ("The Young Turks", "UC1yBKRuGpC1tSM73A0ZjYjQ"),
    ("Jimmy Kimmel Live", "UCa6vGFO9ty8v5KZJXQxdhaw"),
    ("Late Show Stephen Colbert", "UCMtFAi84ehTSYSE9XoHefig"),
    ("Last Week Tonight", "UC3XTzVzaHQEd30rQbuvCtTQ"),
    ("Daily Show", "UCwWhs_6x42TyRM4Wstoq8HA"),
    ("LWIAY (PewDiePie)", "UC-lHJZR3Gqxm24_Vd_AJ5Yw"),
    ("Markiplier", "UC7_YxT-KID8kRbqZo7MyscQ"),
    ("Jacksepticeye", "UCYzPXprvl5Y-Sf0g4vX-m6g"),
    ("Game Theory", "UCo_IB5145EVNcf8hw1Kku7w"),
    ("Watch Mojo", "UCaWd5_7JhbQBe4dknZhsHJg"),
    ("BuzzFeed Unsolved Network", "UCS_AeBSPg99cAErzd-pyhDA"),
    ("Good Mythical Morning", "UC4PooiX37Pld1T8J5SYT-SQ"),
    ("Vat19", "UCC5KEjj2eYxItDXjAm7yHRQ"),
    ("Dude Perfect", "UCRijo3ddMTht_IHyNSNXpNQ"),
    ("Bon Appetit", "UCbpMy0Fg74eXXkvxJrtEn3w"),
    ("Babish Culinary Universe", "UCJHA_jMfCvEnv-3kRjTCQXw"),
    ("Joshua Weissman", "UChBEbMKI1eCcejTtmI32UEw"),
    ("Adam Ragusea", "UC9_p50tH3WmMslWRWKnM7dQ"),
    ("Chef Jean-Pierre", "UCKwzN3uEvtoG8nyqDeg2y3w"),
    ("Ethan Chlebowski", "UCDq5v10l4wkV5-ZBIJJFbzQ"),
    ("Pro Home Cooks", "UCzH5n3Ih5kgQoiDAQt2FwLw"),
    ("Sorted Food", "UCfyehHM_eo4g5JUyWmms2LA"),
    ("America's Test Kitchen", "UCxqq3hp48qWXVPVoWuJI4Ng"),
    ("Bon Appetit Test Kitchen", "UCK1Wnu-7ApfX2GsBy_NyTpA"),
    ("Townsends", "UClFSU9_bUb4Rc6OYfTt5SPw"),
    ("Tasty", "UCJFp8uSYCjXOMnkUyb3CQ3Q"),
    ("Yes Theory", "UCRevtfqWZWdj8Tj-7zJ5pmA"),
    ("Beast Philanthropy", "UCAiLfjNXkNv24uhpzUgPa6A"),
    ("Mr. Beast", "UCX6OQ3DkcsbYNE6H8uQQuVA"),
    ("Smosh", "UCY30JRSgfhYXA6i6xX1erWg"),
    ("Donut Media", "UCYzrCv8RfcGcWHbVNAm5gKw"),
    ("Engineering Explained", "UClqhvGmHcvWL9w3R48t9QXQ"),
    ("Doug DeMuro", "UCsqjHFMB_JYTaEnf_vmTNqg"),
    ("Hoonigan", "UCgvqEhyMs73xX-T8MNUOMmA"),
    ("Top Gear", "UCjOl2AUblVmg2rA_cRgZkFg"),
    ("/DRIVE", "UC8j5UYWBy43AmWcU2K3yEzg"),
]

# ---------------------------------------------------------------------------
# Substack publications — (display name, hostname). Substack RSS at
# https://<host>/feed
# ---------------------------------------------------------------------------

SUBSTACKS = [
    ("Astral Codex Ten", "astralcodexten.substack.com"),
    ("Slow Boring (Matt Yglesias)", "www.slowboring.com"),
    ("Noahpinion", "www.noahpinion.blog"),
    ("Lenny's Newsletter", "www.lennysnewsletter.com"),
    ("Pragmatic Engineer", "newsletter.pragmaticengineer.com"),
    ("Not Boring (Packy McCormick)", "www.notboring.co"),
    ("Stratechery", "stratechery.com"),
    ("The Diff (Byrne Hobart)", "www.thediff.co"),
    ("Doomberg", "doomberg.substack.com"),
    ("The Honest Broker (Ted Gioia)", "www.honest-broker.com"),
    ("Garbage Day", "www.garbageday.email"),
    ("Erik Hoel", "www.theintrinsicperspective.com"),
    ("Maximum Truth", "www.maximumtruth.org"),
    ("Glenn Greenwald", "greenwald.substack.com"),
    ("Matt Taibbi - Racket News", "www.racket.news"),
    ("Andrew Sullivan - Weekly Dish", "andrewsullivan.substack.com"),
    ("Heather Cox Richardson", "heathercoxrichardson.substack.com"),
    ("Bari Weiss - Free Press", "www.thefp.com"),
    ("Persuasion (Yascha Mounk)", "www.persuasion.community"),
    ("Tangle News", "www.readtangle.com"),
    ("Construction Physics", "www.construction-physics.com"),
    ("Marginal Revolution", "marginalrevolution.com"),
    ("Conversable Economist (Tim Taylor)", "conversableeconomist.com"),
    ("Money Stuff (Matt Levine)", "www.bloomberg.com"),
    ("Net Interest (Marc Rubinstein)", "www.netinterest.co"),
    ("Stratechery Daily Update", "stratechery.passport.online"),
    ("Patrick OShaughnessy - Invest Like Best", "investlikethebest.substack.com"),
    ("Money Stuff substack mirror", "moneystuff.substack.com"),
    ("Snippet Finance", "snippetfinance.substack.com"),
    ("Bits about Money (Patrick McKenzie)", "www.bitsaboutmoney.com"),
    ("Kalshi blog", "kalshi.com"),
    ("Dan Wang", "danwang.co"),
    ("Maverick Capital Partners", "maverickcapitalpartners.substack.com"),
    ("Stratechery Articles", "stratechery.com"),
    ("The Information Pro", "www.theinformation.com"),
    ("PJVogt - Search Engine", "searchengine.show"),
    ("Aella - Knowingless", "knowingless.substack.com"),
    ("Lyman Stone", "lymanstone.substack.com"),
    ("Razib Khan - Unsupervised Learning", "razib.substack.com"),
    ("Tyler Cowen Conversations", "conversationswithtyler.com"),
    ("Scott Alexander - Codex", "www.codex.com"),
    ("Pirate Wires (Mike Solana)", "www.piratewires.com"),
    ("ParkerMolloy", "parkermolloy.com"),
    ("Casey Newton - Platformer", "www.platformer.news"),
    ("Charlie Warzel - Galaxy Brain", "warzel.substack.com"),
    ("Ryan Broderick - Garbage Day", "www.garbageday.email"),
    ("Robert Reich", "robertreich.substack.com"),
    ("Paul Krugman", "paulkrugman.substack.com"),
    ("Joyce Vance - Civil Discourse", "joycevance.substack.com"),
    ("Marc Elias - Democracy Docket", "www.democracydocket.com"),
    ("Steady (Dan Rather)", "steady.substack.com"),
    ("Letters from an American", "heathercoxrichardson.substack.com"),
    ("The Bulwark", "www.thebulwark.com"),
    ("The Dispatch", "thedispatch.com"),
    ("Liberal Patriot", "www.liberalpatriot.com"),
    ("Sebastian Sammet", "www.semafor.com"),
    ("ChinaTalk (Jordan Schneider)", "www.chinatalk.media"),
    ("Sinocism", "sinocism.com"),
    ("CarbonBrief", "www.carbonbrief.org"),
    ("Volts (David Roberts)", "www.volts.wtf"),
    ("Heatmap News", "heatmap.news"),
    ("The Climate Brink", "www.theclimatebrink.com"),
    ("Vital Signs (Bill McKibben)", "billmckibben.substack.com"),
    ("Inside Climate News", "insideclimatenews.org"),
    ("Marker (Steven Levy)", "marker.medium.com"),
    ("Substack Reads", "on.substack.com"),
    ("Substack Engineering", "engineering.substack.com"),
    ("Read Max (Max Read)", "maxread.substack.com"),
    ("Embedded (Kate Lindsay & Nick Catucci)", "www.embedded.substack.com"),
    ("Today in Tabs", "www.todayintabs.com"),
    ("Drift Mag", "www.driftmag.com"),
    ("Money Stuff Plus (Bloomberg)", "newsletters.bloomberg.com"),
    ("MicroSaaS Idea", "microsaasidea.substack.com"),
    ("The Generalist", "www.readthegeneralist.com"),
    ("Reforge", "www.reforge.com"),
    ("First Round Review", "review.firstround.com"),
    ("Bessemer Venture Partners", "www.bvp.com"),
    ("a16z", "a16z.com"),
    ("Fred Wilson - AVC", "avc.com"),
    ("Mark Suster - Both Sides of the Table", "bothsidesofthetable.com"),
    ("Tomasz Tunguz", "tomtunguz.com"),
    ("Public Comps", "publiccomps.com"),
    ("App Economy Insights", "appeconomyinsights.com"),
    ("ShoeMoney", "www.shoemoney.com"),
    ("Ben Thompson - Daily Update Free", "stratechery.com"),
    ("Sahil Bloom", "www.sahilbloom.com"),
    ("Trung Phan", "www.trungphan.com"),
    ("Justin Welsh", "www.justinwelsh.me"),
    ("Naval Almanack", "nav.al"),
    ("Visualizing Economics", "visualizingeconomics.substack.com"),
    ("Big Technology (Alex Kantrowitz)", "www.bigtechnology.com"),
    ("The New Atlantis", "www.thenewatlantis.com"),
    ("Tablet Magazine", "www.tabletmag.com"),
    ("The Free Press", "www.thefp.com"),
    ("Common Sense (Bari Weiss old)", "bariweiss.substack.com"),
    ("Public (Michael Shellenberger)", "public.substack.com"),
    ("Racket (Matt Taibbi)", "taibbi.substack.com"),
    ("Substack News", "blog.substack.com"),
]

# ---------------------------------------------------------------------------
# Subreddit list (~800 popular subreddits — RSS URL template).
# ---------------------------------------------------------------------------

SUBREDDITS = """
news worldnews politics technology science askreddit todayilearned funny pics gaming
movies music sports books television aww gifs videos showerthoughts dataisbeautiful
askscience explainlikeimfive lifeprotips iama nottheonion mildlyinteresting tifu
crazyideas writingprompts food cooking recipes fitness loseit getmotivated decidingtobebetter
selfimprovement productivity zenhabits stoicism philosophy history askhistorians
oldschoolcool europe canada australia unitedkingdom india china japan korea germany france
italy spain mexico brazil russia ukraine israel iran turkey poland sweden norway denmark
finland greece thailand vietnam philippines indonesia singapore newzealand argentina chile
colombia venezuela peru southafrica nigeria egypt saudi arabia uae morocco
nfl nba mlb nhl soccer cricket formula1 motogp tennis golf ufc boxing mma running
cycling climbing skateboarding snowboarding skiing surfing fishing hunting
android iphone apple google microsoft amazon meta tesla spacex bitcoin ethereum
cryptocurrency cryptomarkets stocks investing wallstreetbets personalfinance financialindependence
fire frugal eatcheapandhealthy povertyfinance leanfire fatfire chubbyfire bogleheads
linux opensource programming learnprogramming python javascript java rust golang cpp ruby
swift kotlin typescript reactjs vuejs angular svelte rails django flask fastapi nodejs
webdev frontend backend devops sysadmin selfhosted homelab homelabsales kubernetes docker
aws azure googlecloud digitalocean linode dataisugly visualization tableau powerbi
machinelearning artificialintelligence chatgpt openai claudeai bing chatgptcoding
cybersecurity netsec hacking blueteamsec redteamsec
mac macgaming macapps macsetups macsoftware ios ipad ipadpro iosjailbreak applewatch
homekit homeautomation
photography photocritique itookapicture earthporn cityporn skyporn waterporn villageporn
abandonedporn militaryporn natureismetal
art design userexperience userexperiencedesign typography logodesign graphic_design
illustration sketches digitalart pixelart conceptart anime manga anime_irl
books bookclub literature ya scifi fantasy horror writing books_writing
movies horror scifimovies trueromancy popheads hiphopheads metalcore djent
truecrime serialkillers unresolvedmysteries paranormal alienporn
diy crafts knitting sewing woodworking metalworking 3dprinting electronics arduino
raspberry_pi homeimprovement house plants gardening succulents bonsai indoorgarden
landscaping
travel solotravel travelhacks awardtravel onebag camping backpacking hiking
roadtrip motorcycles cars carporn whatcarshouldibuy bicycling bikecommuting
formula1 gtsport gtaonline pcgaming consoles xbox playstation nintendo nintendoswitch
steam steamdeck pcmasterrace buildapc buildapcsales hardwareswap
games tabletopgames boardgames magicthegathering pokemontcg dnd dndnext dndmemes
gamemasters pathfinder warhammerfantasy warhammer40k
askwomen askmen relationship_advice relationships dating dating_advice tinder bumble
askseniors askgaybros lgbt ainbow
philosophyofscience math askphilosophy badphilosophy badscience badeconomics changemyview
publicfreakout instantkarma facepalm cringe trashy iamatotalpieceofshit
unpopularopinion confession offmychest tooafraidtoask nostupidquestions
parenting beyondthebump breastfeeding raisedbynarcissists narcissisticparents
adultchildren adultsurvivors
mentalhealth depression anxiety adhd autism aspergers ocd ptsd cptsd
addiction stopdrinking stopsmoking nofap selfharm
veterans military army navy airforce marines coastguard nationalguard
ems ambulance firefighting medicine nursing residency medicalschool
askdocs psychotherapy therapists counseling
law lawschool law_school lawofficesfm law_school_advice
teachers teaching professors academia askacademia phd gradschool gradschool_admissions
unitedstates askanamerican americanpolitics conservative liberal democrats republicans
libertarian socialism anarchism communism progressive sandersforpresident neoliberal
ukpolitics canadapolitics europe geopolitics worldpolitics anime_titties
foodporn cookingforbeginners eatcheapandhealthy mealprepsunday slowcooking instantpot
sousvide grilling bbq smoking pizza coffee tea cocktails wine whiskey beer homebrewing
veganrecipes plantbaseddiet keto vegan vegetarian glutenfree paleo intermittentfasting
fasting carnivore mealprep
running advancedrunning cycling triathlon swimrun triathletes ultrarunning trailrunning
yoga pilates crossfit weightroom powerlifting bodybuilding xxfitness leangains
bjj martialarts boxing muay_thai kickboxing wrestling judo karate taekwondo
chess chessbeginners anarchychess chesspuzzles correspondencechess gocartograph
go xiangqi shogi
puzzles puzzlevideogames riddles brainteasers wordgames wordreference scrabble crosswords
sudoku
music wearethemusicmakers musicproduction audioengineering vinyl vinylcollectors
hifi audiophile headphones budgetaudiophile diysound diyaudio synthesizers guitars
guitar bass drums classicalmusic jazz electronicmusic edm techno house
trance dubstep drumandbass undergroundhiphop hiphop hiphopcirclejerk popheads
metalcore metal blackmetal deathmetal classicrock progrock prog punk indie indiehead
folk countrymusic kpop jpop anisongs
woodworking woodcarving leathercraft handmade kintsugi origami papercraft
photography astrophotography postprocessing analog filmcameras filmphotography polaroid instax
mediumformat largeformat 35mm slr canon nikon fuji sony pentax leica olympus
ricoh hasselblad mamiya
science askscience explainlikeimfive futurology singularity transhumanism cogsci
neuroscience neuropsychology psychology medicine biology chemistry physics astronomy
geology evolution mathematics math askmath statistics probability datascience
machinelearningnews artificial dailyprogrammer codingweekly compsci theydidthemath
ecology environment climate climateskeptics worldevents collapse
collapseofcivilization
truecrime cold_cases serialkillers unresolvedmysteries unsolved unsolvedmysteries
historymemes historyporn ancientcivilizations ancient_egypt ancientrome ancientgreece
askhistorians historyteachers history_irl propagandaposters militaryhistory
ww2 ww1 coldwar civilwar vietnamwar koreanwar gulfwar warhistorical
religion atheism christianity catholicism protestant islam muslim judaism hindu buddhism
zen taoism paganism wicca asatru norsemythology egyptianmythology greekmythology
nature naturepics natureismetal naturedocumentaries wildlife birding birdwatching whale
ocean oceans sharks turtles dolphins penguins
dogs aww puppies cats cat catpics meow_irl chonkers russianblue blackcats blackcatpics
mainecoon ragdoll persiancats germanshepherds goldenretriever cornerlanding labradors
poodles huskies dachshund corgi
food cooking baking sourdough breadit pizza grilling bbq smoking sousvide
ramen sushi mexicanfood vegetarian vegan ketorecipes carnivore
diet weightloss progresspics fitnesscircle bodyweightfitness running cycling rowing
yoga meditation buddhism zen mindfulness breathwork psychedelics drugs streetwear
sneakers nike adidas yeezys mensfashion malefashionadvice femalefashionadvice
fashion thrift thriftstorehauls onebag minimalism konmari declutter unfuckyourhabitat
cleaningtips homedeco housedecor designdesign
philosophy askphilosophy philosophyofscience philosophyofmind ethics moralphilosophy
askanthropology anthropology sociology economics askeconomics neoliberal
keynesianeconomics austrian_economics marxism_101 communism101 latestagecapitalism
explainlikeimfive eli5
mathmemes nottheonion savedyouaclick clickbaitcouple unethicallifeprotips
askscience medicalmemes psychology economics worldnews internationalpolitics
geopolitics globalpolitics worldevents
todayilearned wikipedia interestingasfuck damnthatsinteresting beamazed
nextfuckinglevel
maps mapporn cartography geography placeism countryballs polandball
askreddit askmen askwomen casualconversation needafriend kindvoice unsentletters
nosleep shortscarystories letsnotmeet creepy creepypasta scarystories rabbits
disney disneyland disneyplus disneymemes disneyfans walt_disney_world
starwars starwarsmemes prequelmemes sequelmemes ot themandalorian
marvelstudios marvelmemes spiderman avengers comicbooks comics legodc
dccinematicverse dccomics batman superman wonderwoman
harrypotter harrypotterboard ravenclaw hufflepuff gryffindor slytherin
lordoftherings tolkienfans tolkienmemes rings_of_power
gameofthrones asoiaf freefolk houseofthedragon
breakingbad bettercallsaul mrrobot succession theofficetv parksandrec brooklyn99
arresteddevelopment community itscharitydetective
strangerthings blackmirror wandavision lokitv lokiseries
naruto onepiece dragonball attackontitan myheroacademia jujutsukaisen demonslayer
spyxfamily chainsawman vinlandsaga berserk
gachagaming genshin_impact zenlesszonezero honkaistarrail honkaiimpact3
mihoyo wuwa games
soccer soccerstreams football championsleague premierleague laliga bundesliga seriea
ligue1 mls
nba nbafromhome nbatalk lakers warriors celtics knicks heat
nfl 49ers patriots cowboys eagles chiefs ravens packers steelers
collegefootball cfb collegebasketball ncaa
mlb yankees dodgers redsox cubs giants
nhl rangers bruins canadiens leafs canucks
formula1 formuladank f1technical
oddlysatisfying oddlyterrifying oddlyspecific oddlysuspicious oddlysmooth
crackheadcraigslist subredditdrama tumblrinaction trollxchromosomes hyperboleandahalf
shittyaskscience shittyfoodporn shittyaskhistorians shittylifeprotips shittyseniors
artisanvideos artisanvideosdaily everythingscience askchemistry askbiology askphysics
askastronomy astronomy spaceporn spacephotography exoplanets aliens ufo conspiracy
conspiracytheories cryptography linguistics languagelearning anki spanish frenchimmersion
italian german mandarin japanese learnjapanese korean koreanlanguage chinese
russian polish dutch portuguese norsk swedish finnish greek arabic farsi turkish hindi
""".split()

# Dedupe and clean subreddit names
SUBREDDITS = sorted({s.strip().lower() for s in SUBREDDITS if s.strip()})


def opml_outline(title: str, xml_url: str, html_url: str) -> str:
    return (
        f'      <outline type="rss" text="{html.escape(title)}" title="{html.escape(title)}" '
        f'xmlUrl="{html.escape(xml_url, quote=True)}" htmlUrl="{html.escape(html_url, quote=True)}" />'
    )


def main() -> None:
    out_path = os.path.expanduser("~/Desktop/newsapp-1k-stress-feeds.opml")
    sections = []
    total = 0

    for category, items in CURATED.items():
        outlines = "\n".join(opml_outline(t, x, h) for t, x, h in items)
        sections.append(
            f'    <outline text="{html.escape(category)}" title="{html.escape(category)}">\n'
            f"{outlines}\n"
            f"    </outline>"
        )
        total += len(items)

    # YouTube channels — every channel exposes RSS at videos.xml?channel_id=<ID>
    yt_outlines = "\n".join(
        opml_outline(
            name,
            f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}",
            f"https://www.youtube.com/channel/{cid}",
        )
        for name, cid in YOUTUBE_CHANNELS
    )
    sections.append(
        f'    <outline text="YouTube" title="YouTube">\n'
        f"{yt_outlines}\n"
        f"    </outline>"
    )
    total += len(YOUTUBE_CHANNELS)

    # Substack publications — RSS at <host>/feed
    sub_outlines = "\n".join(
        opml_outline(name, f"https://{host}/feed", f"https://{host}")
        for name, host in SUBSTACKS
    )
    sections.append(
        f'    <outline text="Substack" title="Substack">\n'
        f"{sub_outlines}\n"
        f"    </outline>"
    )
    total += len(SUBSTACKS)

    # Subreddits as one big category. Capped to 50 to keep Reddit's anonymous
    # rate-limiting from dominating the stress test; toggle MAX_SUBREDDITS to
    # widen the corpus if you want to exercise the rate-limit handling path.
    MAX_SUBREDDITS = 50
    capped_subs = SUBREDDITS[:MAX_SUBREDDITS]
    reddit_outlines = "\n".join(
        opml_outline(
            f"r/{name}",
            f"https://www.reddit.com/r/{name}/.rss",
            f"https://www.reddit.com/r/{name}/",
        )
        for name in capped_subs
    )
    sections.append(
        f'    <outline text="Reddit" title="Reddit">\n'
        f"{reddit_outlines}\n"
        f"    </outline>"
    )
    total += len(capped_subs)

    body = "\n".join(sections)
    opml = f'''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>NewsApp stress test feeds</title>
  </head>
  <body>
{body}
  </body>
</opml>
'''

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(opml)

    print(f"Wrote {total} feeds to {out_path}")


if __name__ == "__main__":
    main()
