package net.pranit.wynnmarket.service;

import java.util.*;
import java.util.function.IntFunction;

/**
 * Given a page of items of type T, we will return listings of type P where the listings are the items that have been added
 * in the currPage since the prevPage
 * It may be the case that P and T are the same. However, we will be hashing on type T
 * @param <P> Type of items in the page
 * @param <T> The type the listings should be
 */
public class PageChangeDetector<P, T> {
    private final int PAGE_SIZE;
    private final IntFunction<T[]> pageFactory;

    private final T[] prevPage;
    private final Map<T, ArrayList<Integer>> prevPageMap;
    private final T[] currPage;
    private final Map<T, ArrayList<Integer>> currPageMap;

    /**
     * Constructor
     * @param pageSize Number of listings on a page
     * @param prevPage The previous page
     * @param currPage The current page
     * @param pageFactory Used to create an empty array of listing items
     */
    public PageChangeDetector(
        int pageSize,
        T[] prevPage,
        T[] currPage,
        IntFunction<T[]> pageFactory
    ) {
        PAGE_SIZE = pageSize;
        this.pageFactory = pageFactory;

        this.prevPage = prevPage;
        this.currPage = currPage;
        this.prevPageMap = populateMap(prevPage);
        this.currPageMap = populateMap(currPage);
    }

    /**
     * Find the listings that have been added to the auction house upon page update
     * @return a list of the listings that are new to the auction house
     */
    public T[] findPageDiff() {
        //Search the current page until a listing from the previous page is found
        for(int slotIndex = 0; slotIndex < PAGE_SIZE; slotIndex++) {
            T currListing = currPage[slotIndex];
            if(currListing == null) return Arrays.copyOfRange(currPage, 0, slotIndex); //Return early if there are null values. Not worth the trouble
            //We come across a listing that appears to be in the old page
            if (prevPageMap.containsKey(currListing)) {
                /*  There could be listings that have the same unique ID in the prevPage.
                    We will start with the ones closer to the page because it is only possible for the later listing
                    to be the currListing if the earlier listing is not
                */
                ArrayList<Integer> possibleListingSlots = prevPageMap.get(currListing);
                for(Integer possibleListingSlot: possibleListingSlots) {
                    /*If valid, this means that we have come across the earliest possible listing in the currPage
                    that was also present in the prevPage. We have also checked that this listing was actually in the prevPage
                     */
                    boolean validListing = checkValidItem(slotIndex, possibleListingSlot, 5, 5);
                    if (validListing) return Arrays.copyOfRange(currPage, 0, slotIndex);
                }
            }
        }
        /*If we get to this point, then something has gone wrong. It's possible that no new listings are there. It is also possible
        but extremely unlikely that enough listings got added such that there were not enough listings left to check validity because
        the new listings got added up until the end of the page
         */
        return pageFactory.apply(0);
    }

    /**
     * Given an item in the currPage that appears to belong in the prevPage, we will check if this item truly appeared in the old page.
     * We can do this by looking at the items after this item in the currPage and see if they truly appeared after this item in the prevPage.
     * If we find such an occurrence, we call this a relative order. This is because we are looking at the relative order, not the absolute order.
     * For example, ABCD -> AD due to two deletes. We would still call AD one relative order because D appears after A.
     * However, we would expend two deletions
     *
     * We take a Two Pointer Approach to comparing the two lists.
     *
     *
     * @param currPageListingSLot The slot of trade market listing in the currPage for which we are checking the validity of
     * @param prevPageListingSlot The slot that we believe the trademarket listing is in the prevPage
     * @param r The number of relative orders that need to be seen to prove the validity of the item
     * @param d The number of perceived deletions that can be seen before this item is declared invalid. Remember deletes are rare
     * @return We return True if the item is this item is a valid prevPage item. However,
     */
    private boolean checkValidItem(int currPageListingSLot, int prevPageListingSlot, int r, int d) {
        int numRel = 0;
        int numDel = 0;
        int currPageSlotIncrements = 0;
        int prevPageSlotIncrements = 0; //Two Pointer Approach

        //We will do this until we see proof of validity r times
        while (numRel < r) {
            //If the next listing we are checking is past the first page, just skip
            if ((currPageListingSLot + currPageSlotIncrements + 1 >= PAGE_SIZE) ||
                (prevPageListingSlot + prevPageSlotIncrements + 1) >= PAGE_SIZE) {
                return false;
            }
            //This should be the next listing in the sequence of listings starting at the first unconfirmedListing
            T listingAfter = currPage[currPageListingSLot + currPageSlotIncrements + 1];
            T supposedListingAfter = prevPage[prevPageListingSlot + prevPageSlotIncrements + 1];
            /*If not equal, either our unconfirmedListing is a new listing that it is not in the prevPage
            or the listing immediately after got deleted. For example, we have ABD in the curr page but ABCD in the prevPage.
            We will just check to see if D is two
             */
            if (!Objects.equals(listingAfter, supposedListingAfter)) {
                /*We will assume that an item in the prevPage got deleted. So if prevPage = ABCD
                and currPage = ABD, advance past C in the previous page and compare D again.
                 */
                prevPageSlotIncrements += 1;
                numDel += 1;
                //Deletions are rare, so if we see too many of them it's a sign to return early
                if (numDel > d) {
                    return false;
                }
            }
            //Check the next relative order. For example, we have found B is after A. Now check if C is after that.
            else {
                currPageSlotIncrements += 1;
                prevPageSlotIncrements += 1;
                numRel += 1;
            }

        }

        //If we have got to this point, then numRel >= r, so the listing was present in the first page
        return true;
    }

    /**
     * Convert a page of listings to a hashmap of listings
     * @param page The page of listings
     * @return a hashmap of listings
     */
    private Map<T, ArrayList<Integer>> populateMap(T[] page) {
        Map<T, ArrayList<Integer>> pageMap = new HashMap<>();

        for (int slotIndex = 0; slotIndex < PAGE_SIZE; slotIndex++) {
            T listing = page[slotIndex];
            if (listing == null) continue;

            pageMap.computeIfAbsent(listing, key -> new ArrayList<>()).add(slotIndex);
        }

        return pageMap;
    }
}
