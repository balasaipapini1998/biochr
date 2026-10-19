# Databricks notebook source
# Deliberately trivial — this notebook is never executed during the sandbox
# tests. Only the job DEFINITION matters.
dbutils.widgets.text("env", "dev")
env = dbutils.widgets.get("env")
print(f"customer_ingest running in {env}")
