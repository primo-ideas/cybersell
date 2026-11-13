use std::fmt;
use std::str::FromStr;

/// Battle.net regions served by `{region}.api.blizzard.com`. China uses other
/// hosts and is not supported.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Region {
    Us,
    Eu,
    Kr,
    Tw,
}

impl Region {
    pub const ALL: [Region; 4] = [Region::Us, Region::Eu, Region::Kr, Region::Tw];

    pub fn as_str(self) -> &'static str {
        match self {
            Region::Us => "us",
            Region::Eu => "eu",
            Region::Kr => "kr",
            Region::Tw => "tw",
        }
    }
}

impl fmt::Display for Region {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Which game a market belongs to: World of Warcraft as it is today, or its progression
/// Classic, Mists of Pandaria Classic at the moment. Each has realms, items and auction
/// houses of its own, under Battle.net namespaces of its own.
///
/// Classic Era, Hardcore, Season of Discovery and Anniversary realms are left out: their
/// namespaces list auction houses, but answer 404 for what is on sale in them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Edition {
    Retail,
    Classic,
}

impl Edition {
    pub const ALL: [Edition; 2] = [Edition::Retail, Edition::Classic];

    /// As stored in the `edition` columns.
    pub fn as_str(self) -> &'static str {
        match self {
            Edition::Retail => "retail",
            Edition::Classic => "classic",
        }
    }

    /// Put before a region to name its markets of this edition, as Battle.net does in its
    /// namespaces: `eu`, `classic-eu`.
    fn prefix(self) -> &'static str {
        match self {
            Edition::Retail => "",
            Edition::Classic => "classic-",
        }
    }

    /// Classic lists everything on each realm's auction house.
    pub fn has_commodities(self) -> bool {
        self == Edition::Retail
    }
}

impl fmt::Display for Edition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// The markets of one region in one edition: `eu`, or `classic-eu`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Market {
    pub edition: Edition,
    pub region: Region,
}

impl Market {
    pub fn retail(region: Region) -> Self {
        Self {
            edition: Edition::Retail,
            region,
        }
    }

    pub fn classic(region: Region) -> Self {
        Self {
            edition: Edition::Classic,
            region,
        }
    }

    /// The `region` of its rows in `auction_houses` and `realms`, which the site shows in
    /// its addresses, and the end of its Battle.net namespaces: `dynamic-classic-eu`.
    pub fn key(self) -> String {
        format!("{}{}", self.edition.prefix(), self.region)
    }

    fn parse(value: &str) -> Option<Self> {
        // Classic first: its prefix would otherwise be taken for part of a region.
        Edition::ALL.into_iter().rev().find_map(|edition| {
            let region = value.strip_prefix(edition.prefix())?;
            let region = Region::ALL
                .into_iter()
                .find(|known| known.as_str() == region)?;
            Some(Self { edition, region })
        })
    }
}

impl fmt::Display for Market {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.key())
    }
}

/// Which connected realms of a region to follow. Its commodity market, where it has one,
/// is always followed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RealmSelection {
    CommoditiesOnly,
    All,
    Slugs(Vec<String>),
}

impl RealmSelection {
    fn merged_with(self, other: RealmSelection) -> RealmSelection {
        use RealmSelection::{All, CommoditiesOnly, Slugs};
        match (self, other) {
            (All, _) | (_, All) => All,
            (CommoditiesOnly, selection) | (selection, CommoditiesOnly) => selection,
            (Slugs(mut slugs), Slugs(more)) => {
                slugs.extend(more);
                Slugs(slugs)
            }
        }
    }
}

/// What to fetch.
///
/// Written as comma-separated entries: `eu` for a whole region, `eu/hyjal` for
/// one realm, `eu/commodities` for the commodity market alone. The same with
/// `classic-` before the region for Mists of Pandaria Classic: `classic-eu`,
/// `classic-eu/everlook`. Empty means every realm of every region, Classic left out.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Scope(Vec<(Market, RealmSelection)>);

impl Scope {
    pub fn everything() -> Self {
        Self(
            Region::ALL
                .into_iter()
                .map(|region| (Market::retail(region), RealmSelection::All))
                .collect(),
        )
    }

    pub fn single(market: Market, selection: RealmSelection) -> Self {
        Self(vec![(market, selection)])
    }

    pub fn markets(&self) -> &[(Market, RealmSelection)] {
        &self.0
    }

    fn add(&mut self, market: Market, selection: RealmSelection) {
        match self.0.iter_mut().find(|(known, _)| *known == market) {
            Some((_, existing)) => {
                let current = std::mem::replace(existing, RealmSelection::CommoditiesOnly);
                *existing = current.merged_with(selection);
            }
            None => self.0.push((market, selection)),
        }
    }
}

const COMMODITIES_SLUG: &str = "commodities";

impl FromStr for Scope {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, String> {
        if value.trim().is_empty() {
            return Ok(Self::everything());
        }

        let mut scope = Self(Vec::new());
        for entry in value
            .split(',')
            .map(str::trim)
            .filter(|entry| !entry.is_empty())
        {
            let entry = entry.to_lowercase();
            let (region, realm) = match entry.split_once('/') {
                Some((region, realm)) => (region, Some(realm)),
                None => (entry.as_str(), None),
            };
            let market = Market::parse(region).ok_or_else(|| {
                format!(
                    "unknown region '{region}' in '{entry}': expected us, eu, kr or tw, \
                     or one of them after classic-"
                )
            })?;
            let selection = match realm {
                None => RealmSelection::All,
                Some("") => return Err(format!("missing realm after '/' in '{entry}'")),
                Some(COMMODITIES_SLUG) if !market.edition.has_commodities() => {
                    return Err(format!(
                        "no commodity market in '{entry}': Classic sells everything on each realm"
                    ));
                }
                Some(COMMODITIES_SLUG) => RealmSelection::CommoditiesOnly,
                Some(slug) => RealmSelection::Slugs(vec![slug.to_owned()]),
            };
            scope.add(market, selection);
        }
        if scope.0.is_empty() {
            return Err(format!("no region or realm in '{value}'"));
        }
        Ok(scope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use RealmSelection::{All, CommoditiesOnly, Slugs};

    fn parse(value: &str) -> Vec<(Market, RealmSelection)> {
        value.parse::<Scope>().unwrap().markets().to_vec()
    }

    const EU: Market = Market {
        edition: Edition::Retail,
        region: Region::Eu,
    };
    const US: Market = Market {
        edition: Edition::Retail,
        region: Region::Us,
    };

    #[test]
    fn empty_means_everything() {
        assert_eq!(parse(""), Scope::everything().markets());
        assert_eq!(parse("  "), Scope::everything().markets());
        assert_eq!(parse("").len(), 4);
        assert!(parse("").iter().all(|(_, selection)| *selection == All));
    }

    #[test]
    fn a_region_alone_means_all_its_realms() {
        assert_eq!(parse("eu"), [(EU, All)]);
    }

    #[test]
    fn a_realm_selects_it_within_its_region() {
        assert_eq!(parse("eu/hyjal"), [(EU, Slugs(vec!["hyjal".into()]))]);
    }

    #[test]
    fn commodities_can_be_selected_alone() {
        assert_eq!(parse("us/commodities"), [(US, CommoditiesOnly)]);
    }

    #[test]
    fn entries_of_a_region_are_merged() {
        assert_eq!(
            parse(" EU/Hyjal, eu/archimonde ,us,"),
            [
                (EU, Slugs(vec!["hyjal".into(), "archimonde".into()])),
                (US, All)
            ]
        );
    }

    #[test]
    fn a_whole_region_wins_over_its_realms() {
        assert_eq!(parse("eu/hyjal,eu"), [(EU, All)]);
        assert_eq!(parse("eu,eu/hyjal"), [(EU, All)]);
    }

    #[test]
    fn a_realm_wins_over_commodities_only() {
        assert_eq!(
            parse("eu/commodities,eu/hyjal"),
            [(EU, Slugs(vec!["hyjal".into()]))]
        );
    }

    #[test]
    fn classic_regions_are_markets_of_their_own() {
        assert_eq!(
            parse("eu,classic-eu/everlook,classic-us"),
            [
                (EU, All),
                (Market::classic(Region::Eu), Slugs(vec!["everlook".into()])),
                (Market::classic(Region::Us), All)
            ]
        );
        assert_eq!(Market::classic(Region::Eu).key(), "classic-eu");
        assert_eq!(EU.key(), "eu");
    }

    #[test]
    fn everything_leaves_classic_out() {
        assert!(
            parse("")
                .iter()
                .all(|(market, _)| market.edition == Edition::Retail)
        );
    }

    #[test]
    fn classic_has_no_commodities() {
        assert!(
            "classic-eu/commodities"
                .parse::<Scope>()
                .unwrap_err()
                .contains("no commodity market")
        );
    }

    #[test]
    fn rejects_what_it_cannot_honor() {
        assert!(
            "mars/hyjal"
                .parse::<Scope>()
                .unwrap_err()
                .contains("unknown region 'mars'")
        );
        assert!(
            "eu/"
                .parse::<Scope>()
                .unwrap_err()
                .contains("missing realm")
        );
        assert!(",".parse::<Scope>().is_err());
    }
}
