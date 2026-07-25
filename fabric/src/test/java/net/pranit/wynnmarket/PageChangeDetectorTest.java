package net.pranit.wynnmarket;

import net.pranit.wynnmarket.service.PageChangeDetector;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Random;

import static org.junit.jupiter.api.Assertions.*;


class PageChangeDetectorTest {
    @Test
    @DisplayName("Example Test")
    void exampleTest() {
        assertEquals(4 , 2 + 2);
    }

    @Test
    void auctionPageTest() {
        //Initialize Pages
        Integer[] prevPage = {13, 5, 19, 12, 4, 17, 19, 19, 2, 8,
            9, 8, 12, 11, 3, 15, 11, 14, 16, 7,
            19, 18, 12, 16, 1, 10, 8, 10, 7, 9,
            9, 3, 10, 4, 4, 15, 2, 16, 17, 13,
            19, 14, 1, 11, 15, 15, 11, 11};

        Integer[] currPage = {16, 14, 2, 19, 15, 15, 17, 9, 7, 1,
            13, 5, 19, 12, 4, 17, 19, 19, 2, 8,
            9, 8, 12, 11, 3, 15, 11, 14, 16, 7,
            19, 18, 12, 16, 1, 10, 8, 10, 7, 9,
            9, 3, 10, 4, 4, 15, 2, 16};

        //Check Pages are correct
        assertEquals(prevPage.length, 48);
        assertEquals(currPage.length, 48);

        //Find Page Diff
        PageChangeDetector<Integer, Integer> testAuctionScanner = new PageChangeDetector<>(
            48,
            prevPage,
            currPage,
            Integer[]::new
        );
        Integer[] auctionPageDiff = testAuctionScanner.findPageDiff();

        //Check Page Diff
        assertEquals(auctionPageDiff.length, 10);
        assertArrayEquals(auctionPageDiff, new Integer[]{16, 14, 2, 19, 15, 15, 17, 9, 7, 1});
    }

    @Test
    void auctionPageTestFailure1() {
        //Initialize Pages
        Integer[] prevPage = {2, 19, 6, 8, 0, 15, 2, 19, 18, 18, 17, 0, 8, 7, 6, 8, 2, 11, 4, 6, 14, 5, 4, 13, 16, 6, 18, 8, 7, 0, 12, 17, 7, 15, 13, 17, 7, 2, 13, 17, 1, 5, 2, 5, 8, 15, 3, 13};
        Integer[] currPage = {17, 6, 2, 19, 6, 8, 0, 15, 2, 19, 18, 18, 17, 0, 8, 7, 6, 8, 2, 11, 4, 6, 14, 5, 4, 13, 16, 6, 18, 8, 7, 0, 12, 17, 7, 15, 13, 17, 7, 2, 13, 17, 1, 5, 2, 5, 8, 15};
        Integer[] currPageNewContent = {17, 6};

        //Check Pages are correct
        assertEquals(prevPage.length, 48);
        assertEquals(currPage.length, 48);

        //Find Page Diff
        PageChangeDetector<Integer, Integer> testAuctionScanner = new PageChangeDetector<>(
            48,
            prevPage,
            currPage,
            Integer[]::new
        );
        Integer[] resultAuctionPageDiff = testAuctionScanner.findPageDiff();

        //Check Page Diff
        assertArrayEquals(resultAuctionPageDiff, currPageNewContent,
            "prevPage: " + Arrays.toString(prevPage) +
                "\ncurrPage: " + Arrays.toString(currPage) +
                "\nexpectedNewContent: " + Arrays.toString(currPageNewContent) +
                "\ncalculatedNewContent: " + Arrays.toString(resultAuctionPageDiff));
    }

    @Test
    void auctionPageNullItems() {
        Integer[] prevPage = {null, null, null, null, 0, 15, 2, 19, 18, 18, 17, 0, 8, 7, 6, 8, 2, 11, 4, 6, 14, 5, 4, 13, 16, 6, 18, 8, 7, 0, 12, 17, 7, 15, 13, 17, 7, 2, 13, 17, 1, 5, 2, 5, 8, 15, 3, 13};
        Integer[] currPage = {17, 6, null, null, null, null, 0, 15, 2, 19, 18, 18, 17, 0, 8, 7, 6, 8, 2, 11, 4, 6, 14, 5, 4, 13, 16, 6, 18, 8, 7, 0, 12, 17, 7, 15, 13, 17, 7, 2, 13, 17, 1, 5, 2, 5, 8, 15};
        Integer[] currPageNewContent = {17, 6};

        //Check Pages are correct
        assertEquals(prevPage.length, 48);
        assertEquals(currPage.length, 48);

        //Find Page Diff
        PageChangeDetector<Integer, Integer> testAuctionScanner = new PageChangeDetector<>(
            48,
            prevPage,
            currPage,
            Integer[]::new
        );
        Integer[] resultAuctionPageDiff = testAuctionScanner.findPageDiff();

        //Check Page Diff
        assertArrayEquals(resultAuctionPageDiff, currPageNewContent,
            "prevPage: " + Arrays.toString(prevPage) +
                "\ncurrPage: " + Arrays.toString(currPage) +
                "\nexpectedNewContent: " + Arrays.toString(currPageNewContent) +
                "\ncalculatedNewContent: " + Arrays.toString(resultAuctionPageDiff));
    }

    @Test
    void detectsNewContentWhenAnOldListingWasDeleted() {
        Integer[] prevPage = {1, 2, 3, 4, 5, 6, 7};
        Integer[] currPage = {9, 1, 2, 4, 5, 6, 7};

        PageChangeDetector<Integer, Integer> detector = new PageChangeDetector<>(
            7,
            prevPage,
            currPage,
            Integer[]::new
        );

        assertArrayEquals(new Integer[]{9}, detector.findPageDiff());
    }

    @Test
    void auctionPageFuzzyTest() {
        Random random = new Random();
        int pageSize = 48;
        for(int test = 0; test < 1000; test++) {
            int currPageNewContentSize = random.nextInt(5);
            System.out.println("Test " + Integer.toString(test));
            auctionPageFuzzyTestHelper(pageSize, currPageNewContentSize);
        }
    }

    void auctionPageFuzzyTestHelper(int pageSize, int currPageNewContentSize) {
        //Initialize Pages
        Integer[] prevPage = generateRandomIntegerPage(pageSize);
        Integer[] currPageNewContent = generateRandomIntegerPage(currPageNewContentSize);
        Integer[] currPage = new Integer[pageSize];
        System.arraycopy(
            currPageNewContent,
            0,
            currPage,
            0,
            currPageNewContentSize
        );

        System.arraycopy(
            prevPage,
            0,
            currPage,
            currPageNewContentSize,
            pageSize - currPageNewContentSize
        );

        //Check Pages are correct
        assertEquals(prevPage.length, pageSize);
        assertEquals(currPage.length, pageSize);
        assertEquals(currPageNewContent.length, currPageNewContentSize);

        //Find Page Diff
        PageChangeDetector<Integer, Integer> testAuctionScanner = new PageChangeDetector<>(
            pageSize,
            prevPage,
            currPage,
            Integer[]::new
        );
        Integer[] resultAuctionPageDiff = testAuctionScanner.findPageDiff();

        //Check Page Diff
        assertArrayEquals(resultAuctionPageDiff, currPageNewContent,
            "prevPage: " + Arrays.toString(prevPage) +
                "\ncurrPage: " + Arrays.toString(currPage) +
                "\nexpectedNewContent: " + Arrays.toString(currPageNewContent) +
                "\ncalculatedNewContent: " + Arrays.toString(resultAuctionPageDiff));
    }

    Integer[] generateRandomIntegerPage(int size) {
        Random random = new Random();
        Integer[] page = new Integer[size];

        for (int slot = 0; slot < size; slot++) {
            page[slot] = random.nextInt(20);
        }

        return page;
    }
}
