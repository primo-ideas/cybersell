module MarketsHelper
  # A column header that sorts by this column, and reverses when it already does. The
  # header itself says how the table is sorted: `aria-sort` means nothing on a link.
  def sort_header(label, column, listing, realm, tip: nil, css_class: nil)
    current = listing.sort == column
    dir = if current
      listing.dir == "asc" ? "desc" : "asc"
    else
      listing.default_dir(column)
    end
    arrow = current ? (listing.dir == "asc" ? " ↑" : " ↓") : ""

    tag.th(scope: "col", class: css_class, "aria-sort": (current ? (listing.dir == "asc" ? "ascending" : "descending") : nil)) do
      link_to "#{label}#{arrow}", realm_home_path(realm, **listing_params(listing).merge(sort: column, dir: dir)),
        class: ("is-sorted" if current), data: { tip: tip }
    end
  end

  # A column header that sorts the deals by this column, always in the same direction.
  def deals_sort_header(label, column, deals, realm, tip: nil, css_class: nil)
    current = deals.sort == column
    tag.th(scope: "col", class: css_class, "aria-sort": ("descending" if current)) do
      link_to "#{label}#{" ↓" if current}", realm_deals_path(realm.region, realm.slug, sort: column),
        class: ("is-sorted" if current), data: { tip: tip }
    end
  end

  def listing_page_path(realm, listing, page)
    realm_home_path(realm, **listing_params(listing).merge(sort: listing.sort, dir: listing.dir, page: page))
  end

  # Whatever the reader filtered on, without what is at its default.
  def listing_params(listing)
    { q: listing.query.presence, item_class: listing.item_class, quality: listing.quality }.compact
  end
end
