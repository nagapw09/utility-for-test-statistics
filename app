package main

import (
	"bufio"
	"context"
	"fmt"
	"image/color"
	"io/ioutil"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/yokoe/herschel"
	"github.com/yokoe/herschel/option"

	"golang.org/x/oauth2/google"
	"gopkg.in/Iwark/spreadsheet.v2"
)

var passed, failed, skipped int

func checkError(err error) {
	if err != nil {
		log.Fatalf("%s\n", err)
	}
}

func definesRows(sheet *spreadsheet.Sheet, row int) int {
	colls := sheet.Rows[row]
	for col := 0; col < len(colls); col++ {
		if colls[col].Value == "" {
			return col
		}
	}
	return len(colls)
}

func fillColors(serviceAccountKey, spreadsheetID, tableName string) {

	client, err := herschel.NewClient(option.WithServiceAccountCredentials(serviceAccountKey))
	checkError(err)

	table, err := client.ReadTable(spreadsheetID, tableName)
	checkError(err)

	green := color.RGBA{26, 255, 0, 1}
	red := color.RGBA{255, 0, 0, 0}
	grey := color.RGBA{199, 199, 199, 1}

	table.SetBackgroundColor(4, 0, green)
	table.SetBackgroundColor(5, 0, red)
	table.SetBackgroundColor(6, 0, grey)

	for row := 0; row < table.GetRows(); row++ {
		for col := 0; col < table.GetCols(); col++ {
			if table.GetValue(row, col) == "pass" {
				table.SetBackgroundColor(row, col, color.RGBA{26, 255, 0, 1})
			} else if table.GetValue(row, col) == "fail" {
				table.SetBackgroundColor(row, col, color.RGBA{255, 0, 0, 0})
			} else if table.GetValue(row, col) == "skip" {
				table.SetBackgroundColor(row, col, color.RGBA{199, 199, 199, 1})
			}
		}
	}

	err = client.WriteTable(spreadsheetID, tableName, table)
	checkError(err)
}

func resultTest(sheet *spreadsheet.Sheet, row, col int, resultOfTest string) {
	if strings.HasPrefix(resultOfTest, "PASS") {
		sheet.Update(row, col, "pass")
		passed++
	} else if strings.HasPrefix(resultOfTest, "FAIL") {
		sheet.Update(row, col, "fail")
		failed++
	} else if strings.HasPrefix(resultOfTest, "SKIP") {
		sheet.Update(row, col, "skip")
		skipped++
	}
}

func workingWithTables(tests, serviceAccountKey, spreadsheetID string) {

	var col = 0
	var row = 1

	data, err := ioutil.ReadFile(serviceAccountKey)
	checkError(err)
	config, err := google.JWTConfigFromJSON(data, spreadsheet.Scope)
	checkError(err)
	client := config.Client(context.TODO())
	service := spreadsheet.NewServiceWithClient(client)
	spreadsheet, err := service.FetchSpreadsheet(spreadsheetID)
	checkError(err)
	sheet, err := spreadsheet.SheetByIndex(0)
	checkError(err)

	sheet.Update(row, col, "pipeline")
	row++
	sheet.Update(row, col, "full log file")
	row++
	sheet.Update(row, col, "date")
	row++
	sheet.Update(row, col, "passed")
	row++
	sheet.Update(row, col, "failed")
	row++
	sheet.Update(row, col, "skipped")
	row++

	col = definesRows(sheet, 3)
	day, month, year := time.Now().Date()
	sheet.Update(3, col, fmt.Sprintf("%d.%s.%d", year, month, day))
	container := make(map[string]int)

	for number, row := range sheet.Rows {
		if len(row) < 1 {
			continue
		}
		if strings.HasPrefix(row[0].Value, "Test") {
			container[row[0].Value] = number
		}
	}

	file, err := os.Open(tests)
	checkError(err)
	defer file.Close()

	scanner := bufio.NewScanner(file)

	lastRow := row
	lastRow += len(container)
	for scanner.Scan() {
		if strings.HasPrefix(scanner.Text(), " ") {
			result1 := strings.Split(strings.TrimSpace(scanner.Text()), " ")
			if len(result1) < 3 {
				continue
			}
			if result1[0] != "---" {
				continue
			}
			testName := result1[2]
			resultOfTest := result1[1]

			rowNumber, ok := container[testName]
			if !ok {
				sheet.Update(lastRow, 0, testName)
				container[testName] = lastRow
				rowNumber = lastRow
				lastRow++
			} else {
				sheet.Update(rowNumber, 0, testName)
			}
			resultTest(sheet, rowNumber, col, resultOfTest)
		}
	}
	sheet.Update(4, col, strconv.Itoa(passed))
	sheet.Update(5, col, strconv.Itoa(failed))
	sheet.Update(6, col, strconv.Itoa(skipped))
	err = sheet.Synchronize()
	checkError(err)

	tableName := sheet.Properties.Title
	fillColors(serviceAccountKey, spreadsheetID, tableName)

	if err := scanner.Err(); err != nil {
		checkError(err)
	}
}

func main() {

	if len(os.Args) < 4 {
		fmt.Printf("example of using: ./test_statistics <path_to_test> <path_to_service_key> <table_id>")
		os.Exit(1)
	}

	tests := os.Args[1]
	serviceAccountKey := os.Args[2]
	spreadsheetID := os.Args[3]
	fmt.Printf("Starting application...\npath_to_test = %s path_to_service_key = %s table_id = %s", tests, serviceAccountKey, spreadsheetID)
	workingWithTables(tests, serviceAccountKey, spreadsheetID)
}
