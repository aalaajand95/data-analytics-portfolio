"""Execute the DuckDB cleaning SQL and print the reconciliation report."""
import duckdb, pathlib

sql = pathlib.Path("../sql/01_clean_and_engineer.sql").read_text()
con = duckdb.connect()
# Execute every statement; capture the final SELECT's result.
result = con.execute(sql).fetchdf()
print("Reconciliation:")
print(result.T)

# Quick integrity checks on the output.
df = con.execute("SELECT * FROM analytic").fetchdf()
print("\nAnalytic table shape:", df.shape)
print("Null cells total:", int(df.isnull().sum().sum()))
print("\nTarget balance:")
print(df["readmitted_30"].value_counts())
print(f"  positive rate: {df['readmitted_30'].mean()*100:.2f}%")
print("\ndiag1_group distribution:")
print(df["diag1_group"].value_counts())
print("\ndtypes:")
print(df.dtypes)
